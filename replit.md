# KipuBankV3 - Hardhat Smart Contract Project

## Overview
KipuBankV3 is a Solidity smart contract project implementing a custodial bank that accepts ETH and ERC20 token deposits, converts them to USDC via Uniswap V2, and allows controlled withdrawals. This is a Hardhat-based development and testing environment.

**Last Updated:** November 27, 2025

## Project Architecture

### Technology Stack
- **Smart Contract Language:** Solidity 0.8.30
- **Development Framework:** Hardhat 2.22.0
- **Testing Framework:** Mocha/Chai (via Hardhat Toolbox)
- **Dependencies:**
  - OpenZeppelin Contracts v5.0.0 (AccessControl, ReentrancyGuard, SafeERC20)
  - Uniswap V2 Core & Periphery (for DEX integration)
  - Hardhat plugins: toolbox, contract-sizer, gas-reporter, solhint

### Project Structure
```
├── contracts/
│   ├── KipuBankV3.sol          # Main bank contract
│   ├── interfaces/
│   │   └── IUniswapV2Router.sol
│   └── mocks/
│       ├── ERC20Mock.sol        # Mock ERC20 for testing
│       └── MockUniswapV2Router.sol
├── test/
│   └── KipuBankV3.test.js      # Comprehensive test suite (10 tests)
├── hardhat.config.js            # Hardhat configuration
├── package.json
├── .gitignore
└── .env.example
```

### Smart Contract Features
- **Multi-token deposits:** Accepts ETH, USDC, and whitelisted ERC20 tokens
- **Automatic conversion:** Converts all deposits to USDC via Uniswap V2
- **Security features:**
  - ReentrancyGuard protection
  - Role-based access control (BANK_MANAGER_ROLE)
  - Withdrawal limits per transaction
  - Global bank cap (TVL limit)
  - Slippage protection on swaps
- **Token whitelist system:** Only approved tokens can be deposited
- **Deposit/withdrawal tracking:** Counters per user for auditing

## Recent Changes

### 2025-11-27: Replit Environment Setup
- Fixed package.json versions for compatibility:
  - Updated `@uniswap/v2-periphery` to `1.1.0-beta.0`
  - Updated `solhint-plugin-prettier` to `0.1.0`
- Updated smart contract for OpenZeppelin v5 compatibility:
  - Changed ReentrancyGuard import path from `security/` to `utils/`
  - Replaced deprecated `safeApprove()` with `forceApprove()`
- Created .gitignore for Node.js/Hardhat artifacts
- Added .env.example for environment configuration
- Set up Hardhat Tests workflow
- All 10 tests passing successfully

## Running the Project

### Test the Contracts
The project is configured with a workflow that automatically runs tests:
```bash
npm test
```

This runs the full test suite (10 tests) including:
- Constructor initialization
- Token support management
- ETH deposits with USDC conversion
- Direct USDC deposits
- ERC20 token deposits with swapping
- Withdrawal functionality
- Security validations

### Other Available Commands
```bash
npm run coverage     # Run test coverage analysis
npm run lint         # Lint Solidity files
npm run deploy       # Deploy to Hardhat network (requires script)
```

## Development Notes

### Environment Variables
The project uses dotenv for configuration. Create a `.env` file based on `.env.example` for:
- Private keys (for deployment)
- RPC URLs for different networks
- API keys for Etherscan verification
- CoinMarketCap API for gas reporting

### Network Configuration
Currently configured for:
- Local Hardhat network (chainId: 1337)
- Unlimited contract size enabled for testing

To add more networks (Sepolia, Mainnet), update `hardhat.config.js`.

### Gas Optimization
The contract uses several gas optimization techniques:
- Immutable variables for constants
- Unchecked arithmetic where safe
- Efficient storage patterns
- Custom errors instead of strings

## Security Considerations

### Current Protections
- ReentrancyGuard on all state-changing functions
- Role-based access control for admin functions
- Maximum withdrawal limits
- Global TVL cap
- Slippage protection on DEX swaps
- SafeERC20 for token interactions

### Known Limitations (from README)
- Dependency on trusted Uniswap V2 Router
- No pause mechanism (recommended for production)
- Requires careful BANK_MANAGER role management
- Volatility risk during token conversions

### Before Production
- External security audit required
- Implement pausability mechanism
- Integrate price oracles for validation
- Extended fuzzing tests
- MEV simulation testing

## Testing Status
✅ All 10 tests passing
- Constructor validation
- Token whitelist management
- ETH → USDC conversion
- Direct USDC deposits
- ERC20 → USDC swapping
- Withdrawal logic
- Security validations
- Fallback protection

## User Preferences
None set yet.
