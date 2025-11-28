
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";

/// @title KipuBankV3 (Optimized & Audited Version)
/// @author Kipubank
/// @notice Custodial bank that accepts ETH or ERC20 deposits, swaps everything to USDC,
///         and allows controlled withdrawals.
/// @dev All deposits (ETH or ERC20) are immediately converted to USDC.
///      Uses a UniswapV2-style router for swaps. Enforces non-zero slippage.
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           ROLES
    // =============================================================

    /// @notice Manager role for token support operations
    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");

    // =============================================================
    //                 IMMUTABLE CONFIGURATION
    // =============================================================

    /// @notice Maximum withdrawal per operation (USDC smallest units)
    uint256 public immutable maxWithdrawal;

    /// @notice Total bank cap in USD units (USDC smallest units)
    uint256 public immutable bankCapUSD;

    /// @notice The USDC token (decimals assumed consistent)
    IERC20 public immutable usdc;

    /// @notice Router used to swap tokens (UniswapV2 style)
    IUniswapV2Router public immutable uniswapRouter;

    // =============================================================
    //                        STORAGE
    // =============================================================

    /// @notice User vault balances denominated in USDC
    mapping(address => uint256) private vaultBalance;

    /// @notice Count of deposits per user
    mapping(address => uint256) public depositCount;

    /// @notice Count of withdrawals per user
    mapping(address => uint256) public withdrawalCount;

    /// @notice Supported tokens mapping
    mapping(address => bool) public isTokenSupported;

    /// @notice List of currently supported tokens
    address[] private supportedTokens;

    /// @notice Total USDC deposits stored in the bank
    uint256 public totalDepositsUSD;

    // =============================================================
    //                           ERRORS
    // =============================================================

    /// @notice Reverted when a provided amount is zero or invalid
    error InvalidAmount();

    /// @notice Reverted when token is not in supported list
    /// @param token offending token address
    error TokenNotSupported(address token);

    /// @notice Reverted when requested withdrawal exceeds maximum
    error MaxWithdrawalExceeded();

    /// @notice Reverted when user balance is insufficient
    error InsufficientBalance();

    /// @notice Reverted when deposit exceeds overall cap
    error BankCapExceeded();

    /// @notice Reverted on unauthorized direct ETH transfers
    error DirectTransfer();

    /// @notice Reverted on unexpected fallback calls
    error DirectCall();

    // =============================================================
    //                            EVENTS
    // =============================================================

    /// @notice Emitted when a deposit occurs
    /// @param user depositor
    /// @param token token used (address(0) = ETH)
    /// @param amount amount deposited
    /// @param usdValue USDC credited
    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue);

    /// @notice Emitted when a withdrawal occurs
    /// @param user withdrawer
    /// @param amount amount withdrawn (USDC)
    event WithdrawalMade(address indexed user, uint256 amount);

    /// @notice Emitted when a token becomes supported
    event TokenSupported(address indexed token);

    /// @notice Emitted when a token is removed from support list
    event TokenUnsupported(address indexed token);

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    /// @notice Ensures `amountOutMin` is non-zero to avoid zero-slippage
    modifier ensureSlippage(uint256 amountOutMin) {
        if (amountOutMin == 0) revert InvalidAmount();
        _;
    }

    /// @notice Ensures token is supported
    modifier tokenSupported(address token) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);
        _;
    }

    /// @notice Ensures sufficient balance and withdrawal constraints
    modifier validateWithdrawal(address user, uint256 amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();
        if (vaultBalance[user] < amount) revert InsufficientBalance();
        _;
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @param _maxWithdrawal maximum withdrawal per operation
    /// @param _bankCapUSD total deposit cap
    /// @param _usdc USDC token address
    /// @param _router UniswapV2 router address
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

    // =============================================================
    //                      ADMIN OPERATIONS
    // =============================================================

    /// @notice Adds a token to supported list
    function supportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert InvalidAmount();
        if (isTokenSupported[token]) return;

        isTokenSupported[token] = true;
        supportedTokens.push(token);

        emit TokenSupported(token);
    }

    /// @notice Removes a token from supported list
    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);

        isTokenSupported[token] = false;

        uint256 len = supportedTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[len - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenUnsupported(token);
    }

    // =============================================================
    //                         DEPOSITS
    // =============================================================

    /// @notice Deposit ETH or supported ERC20. Everything is converted to USDC.
    function deposit(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external payable nonReentrant ensureSlippage(amountOutMin) {
        uint256 usdcValue;

        if (token == address(0)) {
            if (msg.value == 0) revert InvalidAmount();
            usdcValue = _swapEthToUSDC(msg.value, amountOutMin);
        } else if (token == address(usdc)) {
            if (amount == 0) revert InvalidAmount();
            usdc.safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = amount;
        } else {
            if (amount == 0) revert InvalidAmount();
            if (!isTokenSupported[token]) revert TokenNotSupported(token);
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = _swapTokenToUSDC(token, amount, amountOutMin);
        }

        uint256 newTotal = totalDepositsUSD + usdcValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded();

        unchecked {
            totalDepositsUSD = newTotal;
            vaultBalance[msg.sender] += usdcValue;
            depositCount[msg.sender] += 1;
        }

        emit DepositMade(msg.sender, token, token == address(0) ? msg.value : amount, usdcValue);
    }

    // =============================================================
    //                        WITHDRAWALS
    // =============================================================

    /// @notice Withdraw USDC
    function withdraw(uint256 amount)
        external
        nonReentrant
        validateWithdrawal(msg.sender, amount)
    {
        unchecked {
            vaultBalance[msg.sender] -= amount;
            totalDepositsUSD -= amount;
            withdrawalCount[msg.sender] += 1;
        }

        usdc.safeTransfer(msg.sender, amount);

        emit WithdrawalMade(msg.sender, amount);
    }

    // =============================================================
    //                           VIEWS
    // =============================================================

    function getUserBalance(address user) external view returns (uint256) {
        return vaultBalance[user];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // =============================================================
    //                     SWAP HELPER FUNCTIONS
    // =============================================================

    /// @notice Internal helper to swap ETH → USDC
    /// @dev Uses UniswapV2 router. Caller must send ETH.
    function _swapEthToUSDC(
        uint256 ethAmount,
        uint256 amountOutMin
    ) internal returns (uint256 usdcAmount) {
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

    /// @notice Internal helper to swap ERC20 → USDC
    function _swapTokenToUSDC(
        address token,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 usdcAmount) {
        IERC20(token).approve(address(uniswapRouter), amountIn);

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
    }

    // =============================================================
    //                    FALLBACK PROTECTION
    // =============================================================

    receive() external payable {
        revert DirectTransfer();
    }

    fallback() external payable {
        revert DirectCall();
    }
}
