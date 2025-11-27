// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./mocks/ERC20Mock.sol"; 

/// @title KipuBankV3 (Optimized & Audited Version)
/// @notice Custodial bank that accepts ETH/ERC20 deposits, converts them to USDC,
///         and allows controlled withdrawals.
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");

    // Immutable parameters
    uint256 public immutable maxWithdrawal;
    uint256 public immutable bankCapUSD;
    IERC20 public immutable usdc;
    IUniswapV2Router public immutable uniswapRouter;

    // Storage
    mapping(address => uint256) private vaultBalance;
    mapping(address => uint256) public depositCount;
    mapping(address => uint256) public withdrawalCount;
    mapping(address => bool) public isTokenSupported;
    address[] private supportedTokens;
    uint256 public totalDepositsUSD;

    // Errors
    error InvalidAmount();
    error TokenNotSupported(address token);
    error MaxWithdrawalExceeded();
    error InsufficientBalance();
    error BankCapExceeded();
    error DirectTransfer();
    error DirectCall();

    // Events
    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event WithdrawalMade(address indexed user, uint256 amount);
    event TokenSupported(address indexed token);
    event TokenUnsupported(address indexed token);

    // Modifiers
    modifier ensureSlippage(uint256 amountOutMin) {
        if (amountOutMin == 0) revert InvalidAmount();
        _;
    }

    modifier tokenSupported(address token) {
        if (!isTokenSupported[token]) revert TokenNotSupported(token);
        _;
    }

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

    modifier validateWithdrawal(address user, uint256 amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();
        if (vaultBalance[user] < amount) revert InsufficientBalance();
        _;
    }

    // Constructor
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

    // Admin functions
    function supportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert InvalidAmount();
        if (isTokenSupported[token]) return;

        isTokenSupported[token] = true;
        supportedTokens.push(token);

        emit TokenSupported(token);
    }

    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
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

    // Deposits
    function deposit(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external payable nonReentrant ensureSlippage(amountOutMin) updateDeposit(msg.sender, 0) {
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

        vaultBalance[msg.sender] += usdcValue;
        depositCount[msg.sender]++;
        totalDepositsUSD += usdcValue;

        emit DepositMade(
            msg.sender,
            token,
            token == address(0) ? msg.value : amount,
            usdcValue
        );
    }

    // Withdrawals
    function withdraw(uint256 amount) external nonReentrant validateWithdrawal(msg.sender, amount) {
        unchecked {
            vaultBalance[msg.sender] -= amount;
            totalDepositsUSD -= amount;
            withdrawalCount[msg.sender]++;
        }
        usdc.safeTransfer(msg.sender, amount);
        emit WithdrawalMade(msg.sender, amount);
    }

    // Views
    function getUserBalance(address user) external view returns (uint256) {
        return vaultBalance[user];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // Internal Swap Logic
    function _swapEthToUSDC(uint256 ethAmount, uint256 amountOutMin) internal returns (uint256 usdcAmount) {
        address[] memory path = new address[](2);
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

    function _swapTokenToUSDC(address token, uint256 amountIn, uint256 amountOutMin) internal returns (uint256 usdcAmount) {
        IERC20(token).forceApprove(address(uniswapRouter), amountIn);

        address[] memory path = new address[](2);
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

    // Fallback protection
    receive() external payable {
        revert DirectTransfer();
    }

    fallback() external payable {
        revert DirectCall();
    }
}
