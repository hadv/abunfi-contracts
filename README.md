# Abunfi Contracts

Smart contracts for the Abunfi micro-savings platform, built with Foundry.

## Overview

Abunfi is a micro-savings platform that allows users to deposit small amounts of USDC and automatically allocates funds across multiple DeFi yield strategies. The platform is designed for users in emerging markets who want to earn yield on small amounts of capital.

## Architecture

### Core Contracts

- **AbunfiVault.sol** - Main vault contract that manages user deposits and shares
- **StrategyManager.sol** - Manages strategy allocation and rebalancing
- **IAbunfiStrategy.sol** - Interface for all yield strategies

### Strategy Contracts

- **AaveStrategy.sol** - Aave V3 lending strategy
- **CompoundStrategy.sol** - Compound V3 strategy  
- **LiquidStakingStrategy.sol** - Liquid staking (stETH, rETH)
- **LiquidityProvidingStrategy.sol** - AMM liquidity provision

### Mock Contracts

Located in `src/mocks/` for testing and development purposes.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- Node.js (for additional tooling)

### Installation

```bash
# Clone the repository
git clone https://github.com/hadv/abunfi-contracts.git
cd abunfi-contracts

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Deployment

### Local Development

```bash
# Start local node
anvil

# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment

```bash
# Deploy to Arbitrum Goerli
forge script script/Deploy.s.sol --rpc-url arbitrum_goerli --broadcast --verify
```

### Mainnet Deployment

```bash
# Deploy to Arbitrum mainnet
forge script script/Deploy.s.sol --rpc-url arbitrum --broadcast --verify
```

## Testing

```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-contract BasicSetupTest
```

## License

MIT License

## Integration

This contracts repository is designed to be consumed by the main Abunfi application.
