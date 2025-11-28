// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./mocks/ERC20Mock.sol";

/// @title KipuBankV3 (Optimized & Audited Version)
/// @author gisel
/// @notice Custodial bank that accepts ETH/ERC20 deposits, converts them to USDC,
///         and allows controlled withdrawals. All deposits are converted to USDC.
/// @dev This contract relies on an external UniswapV2-like router interface.
///      The contract disallows zero slippage parameters (amountOutMin == 0).
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======== Roles ========
    /// @notice Manager role for token support operations
    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");

    // ======== Immutables / Config ========
    /// @notice Maximum withdrawal per operation (USDC smallest units)
    uint256 public immutable maxWithdrawal;
    /// @notice Total bank cap in USD units (USDC smallest units)
    uint256 public immutable bankCapUSD;
    /// @notice The USDC token the bank uses (decimals assumed consistent)
    IERC20 public immutable usdc;
    /// @notice Router used to swap tokens (UniswapV2 style)
    IUniswapV2Router public immutable uniswapRouter;

    // ======== Storage ========
    /// @notice User vault balances denominated in USDC (USDC smallest units)
    mapping(address => uint256) private vaultBalance;
    /// @notice Count of deposits per user
    mapping(address => uint256) public depositCount;
    /// @notice Count of withdrawals per user
    mapping(address => uint256) public withdrawalCount;
    /// @notice Supported tokens mapping
    mapping(address => bool) public isTokenSupported;
    /// @notice Array of supported tokens for enumeration
    address[] private supportedTokens;
    /// @notice Total deposits currently held in the bank (USDC smallest units)
    uint256 public totalDepositsUSD;

    // ======== Errors ========
    /// @notice Reverted when provided amount is zero or invalid
    error InvalidAmount();
    /// @notice Reverted when token is not in supported list
    /// @param token offending token address
    error TokenNotSupported(address token);
    /// @notice Reverted when requested withdrawal exceeds per-operation maximum
    error MaxWithdrawalExceeded();
    /// @notice Reverted when user balance is insufficient for operation
    error InsufficientBalance();
    /// @notice Reverted when deposit would exceed bank's overall cap
    error BankCapExceeded();
    /// @notice Reverted on direct ETH transfers
    error DirectTransfer();
    /// @notice Reverted on unknown external calls
    error DirectCall();

    // ======== Events ========
    /// @notice Emitted when a user makes a deposit (token or ETH)
    /// @param user depositor
    /// @param token token provided (address(0) === ETH)
    /// @param amount input amount (for ETH this is wei)
    /// @param usdValue USDC value credited to vault
    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue);

    /// @notice Emitted when a user withdraws USDC
    /// @param user withdrawer
    /// @param amount USDC amount withdrawn
    event WithdrawalMade(address indexed user, uint256 amount);

    /// @notice Emitted when a token becomes supported
    /// @param token token address
    event TokenSupported(address indexed token);

    /// @notice Emitted when a token is removed from supported list
    /// @param token token address
    event TokenUnsupported(address indexed token);

    // ======== Modifiers ========
    /// @notice Ensures `amountOutMin` is non-zero to avoid accidental zero-slippage
    /// @param amountOutMin minimum expected amount out from swap
    modifier ensureSlippage(uint256 amountOutMin) {
        if (amountOutMin == 0) revert InvalidAmount();
        _;
    }

    /// @notice Ensures token is supported
    modifier tokenSupported(address token) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);
        _;
    }

    /// @notice Validates withdrawal limits and balances
    /// @param user account requesting withdrawal
    /// @param amount requested amount
    modifier validateWithdrawal(address user, uint256 amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();
        if (vaultBalance[user] < amount) revert InsufficientBalance();
        _;
    }

    // ======== Constructor ========
    /// @param _maxWithdrawal maximum withdrawal per operation (USDC smallest units)
    /// @param _bankCapUSD total deposit cap for the bank (USDC smallest units)
    /// @param _usdc address of USDC token contract
    /// @param _router address of UniswapV2-like router
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

    // ======== Admin functions ========
    /// @notice Adds a token to the supported list
    /// @param token token address to support
    function supportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert InvalidAmount();
        if (isTokenSupported[token]) return;

        isTokenSupported[token] = true;
        supportedTokens.push(token);

        emit TokenSupported(token);
    }

    /// @notice Removes a token from the supported list
    /// @param token token address to remove
    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);
        isTokenSupported[token] = false;

        uint256 len = supportedTokens.length;
        // minimal writes: swap & pop
        for (uint256 i = 0; i < len; ++i) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[len - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenUnsupported(token);
    }

    // ======== Deposits ========
    /// @notice Deposit ETH or supported ERC20 token. All values are converted to USDC and credited.
    /// @param token token address to deposit (address(0) for ETH, or USDC address to deposit USDC directly)
    /// @param amount token amount to deposit (ignored for ETH; pass 0 when token == address(0))
    /// @param amountOutMin minimum USDC expected from the swap (reverts if 0)
    function deposit(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external payable nonReentrant ensureSlippage(amountOutMin) {
        uint256 usdcValue;

        if (token == address(0)) {
            // ETH deposit
            if (msg.value == 0) revert InvalidAmount();
            usdcValue = _swapEthToUSDC(msg.value, amountOutMin);
        } else if (token == address(usdc)) {
            // Direct USDC deposit
            if (amount == 0) revert InvalidAmount();
            // transfer from user
            usdc.safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = amount;
        } else {
            // ERC20 token deposit and swap to USDC
            if (amount == 0) revert InvalidAmount();
            if (!isTokenSupported[token]) revert TokenNotSupported(token);
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = _swapTokenToUSDC(token, amount, amountOutMin);
        }

        // --- single point of state updates (no duplicates) ---
        // check bank cap before writing
        uint256 newTotal = totalDepositsUSD + usdcValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded();

        // safe gas-optimized writes
        // avoid multiple mapping reads/writes by using unchecked increments for counters
        unchecked {
            totalDepositsUSD = newTotal;
            vaultBalance[msg.sender] = vaultBalance[msg.sender] + usdcValue;
            depositCount[msg.sender] = depositCount[msg.sender] + 1;
        }

        emit DepositMade(msg.sender, token, token == address(0) ? msg.value : amount, usdcValue);
    }

    // ======== Withdrawals ========
    /// @notice Withdraw USDC from your vault
    /// @param amount amount of USDC to withdraw (smallest units)
    function withdraw(uint256 amount) external nonReentrant validateWithdrawal(msg.sender, amount) {
        // single access write pattern
        unchecked {
            vaultBalance[msg.sender] = vaultBalance[msg.sender] - amount;
            totalDepositsUSD = totalDepositsUSD - amount;
            withdrawalCount[msg.sender] = withdrawalCount[msg.sender] + 1;
        }

        usdc.safeTransfer(msg.sender, amount);
        emit WithdrawalMade(msg.sender, amount);
    }

    // ======== Views ========
    /// @notice Get user's USDC balance held in the vault
    /// @param user address to query
    /// @return USDC balance (smallest units)
    function getUserBalance(address user) external view returns (uint256) {
        return vaultBalance[user];
    }

    /// @notice Returns supported tokens list
    /// @return array of supported token addresses
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // ======== Internal swap helpers ========
    /// @dev Swaps ETH -> USDC using router. Caller must send ETH (value).
    function _swapEthToUSDC(uint256 ethAmount, uint256 amountOutMin) internal returns (uint256 usdcAmount) {
        address;
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdc);

        uint256 before = usdc.balanceOf(address(this));

        // router call (revert propagation)
        uniswapRouter.swapExactETHForTokens{value: ethAmount}(amountOutMin, path, address(this), block.timestamp);

        usdcAmount = usdc.balanceOf(address(this)) - before;
    }

    /// @dev Swaps ERC20 token -> USDC using router.
    function _swapTokenToUSDC(address token, uint256 amountIn, uint256 amountOutMin) internal returns (uint256 usdcAmount) {
        // Approve router to spend token. Use SafeERC20 safeIncreaseAllowance if available.
        IERC20(token).approve(address(uniswapRouter), amountIn);

        address;
        path[0] = token;
        path[1] = address(usdc);

        uint256 before = usdc.balanceOf(address(this));
        uniswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp);
        usdcAmount = usdc.balanceOf(address(this)) - before;
    }

    // ======== Fallback protection ========
    receive() external payable {
        revert DirectTransfer();
    }

    fallback() external payable {
        revert DirectCall();
    }
}

