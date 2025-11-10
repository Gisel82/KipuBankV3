//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    uint256 public immutable bankCapUSD;
    IERC20 public immutable usdc;
    AggregatorV3Interface public immutable ethUsdFeed;
    IUniswapV2Router public immutable uniswapRouter;

    // ======================
    //      STATE STORAGE
    // ======================
    mapping(address => mapping(address => uint256)) private vaultBalance; // user => token => balance
    mapping(address => uint256) public depositCount;
    mapping(address => uint256) public withdrawalCount;

    mapping(address => bool) public isTokenSupported;
    address[] private supportedTokens;

    uint256 public totalDepositsUSD;

    // ======================
    //         ERRORS
    // ======================
    error InvalidAmount();
    error TokenNotSupported();
    error MaxWithdrawalExceeded();
    error InsufficientBalance();
    error BankCapExceeded();
    error DirectTransfer();
    error DirectCall();
    error TransferFailed();

    // ======================
    //         EVENTS
    // ======================
    /// @notice Emitted when a deposit occurs
    /// @param user User depositing
    /// @param token Token address deposited (0 for ETH)
    /// @param amount Amount of token deposited
    /// @param usdValue6 Equivalent USDC value (6 decimals)
    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);

    /// @notice Emitted when a withdrawal occurs
    /// @param user User withdrawing
    /// @param token Token withdrawn (always USDC)
    /// @param amount Amount withdrawn
    /// @param usdValue6 Equivalent USDC value
    event WithdrawalMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);

    /// @notice Emitted when a token is supported
    /// @param token Token address
    event TokenSupported(address indexed token);

    /// @notice Emitted when a token is unsupported
    /// @param token Token address
    event TokenUnsupported(address indexed token);

    // ======================
    //      CONSTRUCTOR
    // ======================
    constructor(
        uint256 _maxWithdrawal,
        uint256 _bankCapUSD,
        address _usdc,
        address _ethUsdFeed,
        address _router
    ) {
        if (_maxWithdrawal == 0 || _bankCapUSD == 0) revert InvalidAmount();

        maxWithdrawal = _maxWithdrawal;
        bankCapUSD = _bankCapUSD;
        usdc = IERC20(_usdc);
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        uniswapRouter = IUniswapV2Router(_router);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BANK_MANAGER_ROLE, msg.sender);
    }

    // ======================
    //      ADMIN FUNCTIONS
    // ======================
    function supportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert TokenNotSupported();
        if (!isTokenSupported[token]) {
            isTokenSupported[token] = true;
            supportedTokens.push(token);
            emit TokenSupported(token);
        }
    }

    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (!isTokenSupported[token]) revert TokenNotSupported();
        isTokenSupported[token] = false;

        uint256 len = supportedTokens.length;
        for (uint256 i = 0; i < len; i++) {
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
    function deposit(address token, uint256 amount) external payable nonReentrant {
        uint256 usdcValue;

        if (token == address(0)) {
            if (msg.value == 0) revert InvalidAmount();
            usdcValue = _swapEthToUSDC(msg.value);
        } else if (token == address(usdc)) {
            if (amount == 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = amount;
        } else {
            if (!isTokenSupported[token]) revert TokenNotSupported();
            if (amount == 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            usdcValue = _swapTokenToUSDC(token, amount);
        }

        uint256 newTotal = totalDepositsUSD + usdcValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded();

        totalDepositsUSD = newTotal;

        // Guardar en memoria y luego subir a storage
        uint256 currentBalance = vaultBalance[msg.sender][address(usdc)];
        vaultBalance[msg.sender][address(usdc)] = currentBalance + usdcValue;

        depositCount[msg.sender]++;
        emit DepositMade(msg.sender, token, amount, usdcValue);
    }

    // ======================
    //       WITHDRAWALS
    // ======================
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();

        uint256 balance = vaultBalance[msg.sender][address(usdc)];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            vaultBalance[msg.sender][address(usdc)] = balance - amount;
            totalDepositsUSD -= amount;
        }

        withdrawalCount[msg.sender]++;
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
    function _swapEthToUSDC(uint256 ethAmount) internal returns (uint256 usdcAmount) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        uniswapRouter.swapExactETHForTokens{value: ethAmount}(0, path, address(this), block.timestamp);
        uint256 balanceAfter = usdc.balanceOf(address(this));
        unchecked { usdcAmount = balanceAfter - balanceBefore; }
    }

    function _swapTokenToUSDC(address token, uint256 amountIn) internal returns (uint256 usdcAmount) {
        IERC20(token).safeApprove(address(uniswapRouter), 0);
        IERC20(token).safeApprove(address(uniswapRouter), amountIn);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        uniswapRouter.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
        uint256 balanceAfter = usdc.balanceOf(address(this));
        unchecked { usdcAmount = balanceAfter - balanceBefore; }
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