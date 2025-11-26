// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router.sol";

/// @title KipuBankV3 (Optimized & Audited Version)
/// @author ...
/// @notice Custodial bank that accepts ETH/ERC20 deposits, converts them to USDC,
///         and allows controlled withdrawals.
/// @dev Internal accounting uses USDC (6 decimals). This version includes
///      modifiers, optimized storage access, safe slippage checks, and NatSpec fixes.
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --------------------------------------------------------------------------
    //                                Roles
    // --------------------------------------------------------------------------

    /// @notice Role that allows managing supported tokens.
    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");

    // --------------------------------------------------------------------------
    //                          Immutable parameters
    // --------------------------------------------------------------------------

    /// @notice Maximum USDC withdrawable per transaction.
    uint256 public immutable maxWithdrawal;

    /// @notice Maximum total USDC-denominated liquidity allowed in the bank.
    uint256 public immutable bankCapUSD;

    /// @notice USDC token used as unit of account.
    IERC20 public immutable usdc;

    /// @notice Uniswap V2 compatible router.
    IUniswapV2Router public immutable uniswapRouter;

    // --------------------------------------------------------------------------
    //                                 Storage
    // --------------------------------------------------------------------------

    /// @notice Tracks deposited balances per user in USDC denominations.
    mapping(address => uint256) private vaultBalance;

    /// @notice Number of deposits per user.
    mapping(address => uint256) public depositCount;

    /// @notice Number of withdrawals per user.
    mapping(address => uint256) public withdrawalCount;

    /// @notice Which tokens are allowed for deposit.
    mapping(address => bool) public isTokenSupported;

    /// @notice List of supported tokens.
    address[] private supportedTokens;

    /// @notice Total USDC liquidity in the bank.
    uint256 public totalDepositsUSD;

    // --------------------------------------------------------------------------
    //                                 Errors
    // --------------------------------------------------------------------------

    /// @notice Thrown when amount is zero.
    error InvalidAmount();

    /// @notice Thrown when interacting with unsupported token.
    /// @param token Address of the token attempted.
    error TokenNotSupported(address token);

    /// @notice Withdrawal exceeds maxWithdrawal.
    error MaxWithdrawalExceeded();

    /// @notice User tries to withdraw more than their balance.
    error InsufficientBalance();

    /// @notice Bank capacity exceeded.
    error BankCapExceeded();

    /// @notice Direct transfer of ETH not allowed.
    error DirectTransfer();

    /// @notice Fallback called.
    error DirectCall();

    // --------------------------------------------------------------------------
    //                                Events
    // --------------------------------------------------------------------------

    /// @notice Emitted when a deposit completes.
    /// @param user Depositing user.
    /// @param token Token deposited (ETH uses address(0)).
    /// @param amount Amount of token deposited.
    /// @param usdValue USDC equivalent credited internally.
    event DepositMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue
    );

    /// @notice Emitted when user withdraws USDC.
    /// @param user The withdrawing user.
    /// @param amount Amount of USDC withdrawn.
    event WithdrawalMade(address indexed user, uint256 amount);

    /// @notice A token was added as supported.
    /// @param token Token address supported.
    event TokenSupported(address indexed token);

    /// @notice A token was removed from support.
    /// @param token Token address removed.
    event TokenUnsupported(address indexed token);

    // --------------------------------------------------------------------------
    //                                  Modifiers
    // --------------------------------------------------------------------------

    /// @notice Ensures amountOutMin > 0 for slippage protection.
    modifier ensureSlippage(uint256 amountOutMin) {
        if (amountOutMin == 0) revert InvalidAmount();
        _;
    }

    /// @notice Ensures token is supported.
    modifier tokenSupported(address token) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);
        _;
    }

    /// @notice Applies accounting logic for deposits.
    /// @dev Reduces double storage writes.
    modifier updateDeposit(address user, uint256 usdcValue) {
        uint256 newTotal = totalDepositsUSD + usdcValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded();

        unchecked {
            totalDepositsUSD = newTotal;
            vaultBalance[user] += usdcValue;
            depositCount[user]++;
        }
        _;
    }

    /// @notice Validates withdrawal limits and balance.
    modifier validateWithdrawal(address user, uint256 amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();

        if (vaultBalance[user] < amount) revert InsufficientBalance();
        _;
    }

    // --------------------------------------------------------------------------
    //                                 Constructor
    // --------------------------------------------------------------------------

    constructor(
        uint256 _maxWithdrawal,
        uint256 _bankCapUSD,
        address _usdc,
        address _router
    ) {
        if (_maxWithdrawal == 0 || _bankCapUSD == 0) revert InvalidAmount();
        if (_usdc == address(0) || _router == address(0)) revert InvalidAmount();

        maxWithdrawal = _maxWithdrawal;
        bankCapUSD = _bankCapUSD;
        usdc = IERC20(_usdc);
        uniswapRouter = IUniswapV2Router(_router);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BANK_MANAGER_ROLE, msg.sender);
    }

    // --------------------------------------------------------------------------
    //                               Admin Functions
    // --------------------------------------------------------------------------

    /// @notice Adds a token as depositable.
    function supportToken(address token)
        external
        onlyRole(BANK_MANAGER_ROLE)
    {
        if (token == address(0)) revert InvalidAmount();
        if (isTokenSupported[token]) return;

        isTokenSupported[token] = true;
        supportedTokens.push(token);

        emit TokenSupported(token);
    }

    /// @notice Removes a token from the supported list.
    function unsupportToken(address token)
        external
        onlyRole(BANK_MANAGER_ROLE)
    {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);

        isTokenSupported[token] = false;

        uint256 len = supportedTokens.length;
        for (uint256 i; i < len; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[len - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenUnsupported(token);
    }

    // --------------------------------------------------------------------------
    //                                  Deposits
    // --------------------------------------------------------------------------

    function deposit(
        address token,
        uint256 amount,
        uint256 amountOutMin
    )
        external
        payable
        nonReentrant
        ensureSlippage(amountOutMin)
    {
        uint256 usdcValue;

        if (token == address(0)) {
            // ETH deposit
            if (msg.value == 0) revert InvalidAmount();

            usdcValue = _swapEthToUSDC(msg.value, amountOutMin);

        } else if (token == address(usdc)) {
            // Direct USDC
            if (amount == 0) revert InvalidAmount();
            usdc.safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = amount;

        } else {
            // ERC20 deposit
            if (amount == 0) revert InvalidAmount();
            if (!isTokenSupported[token]) revert TokenNotSupported(token);

            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = _swapTokenToUSDC(token, amount, amountOutMin);
        }

        _updateDeposit(msg.sender, usdcValue);

        emit DepositMade(
            msg.sender,
            token,
            token == address(0) ? msg.value : amount,
            usdcValue
        );
    }

    // --------------------------------------------------------------------------
    //                                Withdrawals
    // --------------------------------------------------------------------------

    function withdraw(uint256 amount)
        external
        nonReentrant
        validateWithdrawal(msg.sender, amount)
    {
        unchecked {
            vaultBalance[msg.sender] -= amount;
            totalDepositsUSD -= amount;
            withdrawalCount[msg.sender]++;
        }

        usdc.safeTransfer(msg.sender, amount);
        emit WithdrawalMade(msg.sender, amount);
    }

    // --------------------------------------------------------------------------
    //                                  Views
    // --------------------------------------------------------------------------

    function getUserBalance(address user)
        external
        view
        returns (uint256)
    {
        return vaultBalance[user];
    }

    function getSupportedTokens()
        external
        view
        returns (address[] memory)
    {
        return supportedTokens;
    }

    // --------------------------------------------------------------------------
    //                              Internal Swap Logic
    // --------------------------------------------------------------------------

    function _swapEthToUSDC(
        uint256 ethAmount,
        uint256 amountOutMin
    )
        internal
        returns (uint256 usdcAmount)
    {
        address;
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdc);

        uint256 before = usdc.balanceOf(address(this));

        uniswapRouter.swapExactETHForTokens{value: ethAmount}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        usdcAmount = usdc.balanceOf(address(this)) - before;
    }

    function _swapTokenToUSDC(
        address token,
        uint256 amountIn,
        uint256 amountOutMin
    )
        internal
        returns (uint256 usdcAmount)
    {
        IERC20(token).safeApprove(address(uniswapRouter), 0);
        IERC20(token).safeApprove(address(uniswapRouter), amountIn);

        address;
        path[0] = token;
        path[1] = address(usdc);

        uint256 before = usdc.balanceOf(address(this));

        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        usdcAmount = usdc.balanceOf(address(this)) - before;

        IERC20(token).safeApprove(address(uniswapRouter), 0);
    }

    // --------------------------------------------------------------------------
    //                         Fallback protection
    // --------------------------------------------------------------------------

    receive() external payable {
        revert DirectTransfer();
    }

    fallback() external payable {
        revert DirectCall();
    }
}

