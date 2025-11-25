// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IUniswapV2Router {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @title KipuBankV3
/// @author ...
/// @notice Banco simple que acepta depósitos y permite retiros en USDC. Internamente convierte tokens/ETH a USDC.
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======================
    //          ROLES
    // ======================
    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");

    // ======================
    //     IMMUTABLE VARS
    // ======================
    uint256 public immutable maxWithdrawal;
    uint256 public immutable bankCapUSD; // denominated in USDC smallest unit (6 decimals)
    IERC20 public immutable usdc;
    IUniswapV2Router public immutable uniswapRouter;

    // ======================
    //      STATE STORAGE
    // ======================
    // user => token => balance (balances always denominated in USDC 6 decimals)
    mapping(address => mapping(address => uint256)) private vaultBalance;
    mapping(address => uint256) public depositCount;
    mapping(address => uint256) public withdrawalCount;

    mapping(address => bool) public isTokenSupported;
    address[] private supportedTokens;

    uint256 public totalDepositsUSD;

    // ======================
    //         ERRORS (NatSpec agregado)
    // ======================
    /// @notice Thrown when an amount is zero or invalid.
    error InvalidAmount();

    /// @notice Thrown when token isn't supported by the bank.
    error TokenNotSupported();

    /// @notice Thrown when requested withdrawal > configured maxWithdrawal.
    error MaxWithdrawalExceeded();

    /// @notice Thrown when user has insufficient balance.
    error InsufficientBalance();

    /// @notice Thrown when deposit would exceed bank cap.
    error BankCapExceeded();

    /// @notice Thrown when a direct ETH transfer (receive) is attempted.
    error DirectTransfer();

    /// @notice Thrown when fallback is invoked.
    error DirectCall();

    /// @notice Thrown when ERC20 transfer fails.
    error TransferFailed();

    // ======================
    //         EVENTS (NatSpec agregado)
    // ======================
    /// @notice Emitted when a deposit occurs.
    /// @param user User depositing.
    /// @param token Token address deposited (address(0) for ETH).
    /// @param amount Amount of token deposited (raw token units or msg.value for ETH).
    /// @param usdValue6 Equivalent USDC value (6 decimals).
    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);

    /// @notice Emitted when a withdrawal occurs.
    /// @param user User withdrawing.
    /// @param token Token withdrawn (always USDC).
    /// @param amount Amount withdrawn (USDC units).
    /// @param usdValue6 Equivalent USDC value (same as amount).
    event WithdrawalMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);

    /// @notice Emitted when a token is supported.
    /// @param token Token address.
    event TokenSupported(address indexed token);

    /// @notice Emitted when a token is unsupported.
    /// @param token Token address.
    event TokenUnsupported(address indexed token);

    // ======================
    //        MODIFIERS
    // ======================
    modifier notZeroAddress(address addr) {
        require(addr != address(0), "zero address");
        _;
    }

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    modifier onlyIfSupported(address token) {
        if (!isTokenSupported[token]) revert TokenNotSupported();
        _;
    }

    // ======================
    //      CONSTRUCTOR
    // ======================
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

    // ======================
    //      ADMIN FUNCTIONS
    // ======================
    /// @notice Mark a token as supported.
    function supportToken(address token) external onlyRole(BANK_MANAGER_ROLE) notZeroAddress(token) {
        if (!isTokenSupported[token]) {
            isTokenSupported[token] = true;
            supportedTokens.push(token);
            emit TokenSupported(token);
        }
    }

    /// @notice Remove token support.
    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (!isTokenSupported[token]) revert TokenNotSupported();
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

    // ======================
    //       DEPOSITS
    // ======================
    /**
     * @notice Deposit tokens or ETH into the bank. All deposits are converted to USDC internally.
     * @param token Token address to deposit (address(0) = ETH). If token == usdc, `amount` is USDC units.
     * @param amount Amount of token to deposit (or 0 for ETH; for ETH use msg.value).
     * @param amountOutMin Minimum acceptable USDC returned by swap (use 0 only when you accept full slippage).
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external payable nonReentrant {
        uint256 usdcValue;

        // 1) gather funds and perform swap when needed
        if (token == address(0)) {
            // ETH deposit: require msg.value and swap
            if (msg.value == 0) revert InvalidAmount();
            usdcValue = _swapEthToUSDC{value: msg.value}(msg.value, amountOutMin);
        } else if (token == address(usdc)) {
            // direct USDC deposit
            if (amount == 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = amount;
        } else {
            // other ERC20 tokens must be supported
            if (amount == 0) revert InvalidAmount();
            if (!isTokenSupported[token]) revert TokenNotSupported();

            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = _swapTokenToUSDC(token, amount, amountOutMin);
        }

        // 2) check bank cap (use local var to avoid multiple storage reads)
        uint256 newTotal = totalDepositsUSD + usdcValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded();
        totalDepositsUSD = newTotal;

        // 3) update user vault (read once, write once)
        uint256 prev = vaultBalance[msg.sender][address(usdc)];
        vaultBalance[msg.sender][address(usdc)] = prev + usdcValue;

        // 4) update counters (using unchecked for tiny gas saving; safe because increment can't overflow realistically)
        unchecked {
            depositCount[msg.sender]++;
        }

        emit DepositMade(msg.sender, token, amount == 0 ? msg.value : amount, usdcValue);
    }

    // ======================
    //       WITHDRAWALS
    // ======================
    /**
     * @notice Withdraw USDC up to `maxWithdrawal` per tx.
     * @param amount Amount of USDC to withdraw (6 decimals).
     */
    function withdraw(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();

        uint256 balance = vaultBalance[msg.sender][address(usdc)];
        if (balance < amount) revert InsufficientBalance();

        // update storage with local values, then transfer
        unchecked {
            vaultBalance[msg.sender][address(usdc)] = balance - amount;
            totalDepositsUSD -= amount;
            withdrawalCount[msg.sender]++;
        }

        usdc.safeTransfer(msg.sender, amount);
        emit WithdrawalMade(msg.sender, address(usdc), amount, amount);
    }

    // ======================
    //          VIEWS
    // ======================
    function getUserBalance(address user) external view returns (uint256) {
        return vaultBalance[user][address(usdc)];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // ======================
    //     INTERNAL HELPERS
    // ======================
    /**
     * @dev Swap ETH -> USDC using router, requires amountOutMin parameter to protect slippage.
     */
    function _swapEthToUSDC(uint256 ethAmount, uint256 amountOutMin) internal returns (uint256 usdcAmount) {
        address;
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        // pass amountOutMin (may be 0 if caller intentionally accepts any amount)
        uniswapRouter.swapExactETHForTokens{value: ethAmount}(amountOutMin, path, address(this), block.timestamp);
        uint256 balanceAfter = usdc.balanceOf(address(this));
        unchecked {
            usdcAmount = balanceAfter - balanceBefore;
        }
    }

    /**
     * @dev Swap ERC20 token -> USDC. Approves exactly amountIn to router.
     */
    function _swapTokenToUSDC(
        address token,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 usdcAmount) {
        // Approve router for amountIn in a safe manner (reset to 0 then set)
        IERC20(token).safeApprove(address(uniswapRouter), 0);
        IERC20(token).safeApprove(address(uniswapRouter), amountIn);

        address;
        path[0] = token;
        path[1] = address(usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        uniswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp);
        uint256 balanceAfter = usdc.balanceOf(address(this));
        unchecked {
            usdcAmount = balanceAfter - balanceBefore;
        }

        // Optional: revoke approval (not necessary; but for safety)
        IERC20(token).safeApprove(address(uniswapRouter), 0);
    }

    // ======================
    //     FALLBACK HANDLERS
    // ======================
    receive() external payable {
        revert DirectTransfer();
    }

    fallback() external payable {
        revert DirectCall();
    }
}

   
       
 
   
