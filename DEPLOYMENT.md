# Abunfi Contracts Deployment Guide

This guide provides comprehensive instructions for deploying Abunfi smart contracts to Sepolia testnet and other networks.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Sepolia Testnet Deployment](#sepolia-testnet-deployment)
- [Contract Verification](#contract-verification)
- [Post-Deployment Testing](#post-deployment-testing)
- [Troubleshooting](#troubleshooting)
- [Network Configurations](#network-configurations)

## Prerequisites

### Required Tools

1. **Foundry** - Smart contract development framework
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Node.js** (v16+) - For additional tooling
   ```bash
   # Install via nvm (recommended)
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
   nvm install 18
   nvm use 18
   ```

3. **Git** - Version control
4. **jq** - JSON processor (for deployment scripts)
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

### Required Accounts and Keys

1. **Ethereum Wallet** with private key
2. **Alchemy/Infura Account** for RPC endpoints
3. **Etherscan Account** for contract verification
4. **Sepolia ETH** for gas fees (get from [Sepolia Faucet](https://sepoliafaucet.com/))

## Environment Setup

### 1. Clone and Install

```bash
git clone https://github.com/hadv/abunfi-contracts.git
cd abunfi-contracts
forge install
npm install  # If using additional Node.js tools
```

### 2. Environment Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env  # or use your preferred editor
```

### 3. Required Environment Variables

```bash
# Essential variables for Sepolia deployment
PRIVATE_KEY=0x1234...  # Your wallet private key (NEVER commit this)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

### 4. Verify Setup

```bash
# Test compilation
forge build

# Run tests
forge test

# Check deployer balance
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $SEPOLIA_RPC_URL
```

## Sepolia Testnet Deployment

### Option 1: Using Deployment Script (Recommended)

```bash
# Make script executable
chmod +x scripts/deploy-sepolia.sh

# Run deployment
./scripts/deploy-sepolia.sh
```

### Option 2: Manual Deployment

```bash
# Deploy core contracts
forge script script/DeploySepolia.s.sol:DeploySepolia \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

### Option 3: Using Package Scripts

```bash
# Deploy to testnet (uses TESTNET_RPC_URL from .env)
npm run deploy:testnet
```

### Deployment Output

After successful deployment, you'll see:

```
=== SEPOLIA DEPLOYMENT SUMMARY ===
Network: Sepolia Testnet
Chain ID: 11155111

📋 Core Contracts:
├── USDC Token: 0x1234...
├── AbunfiVault: 0x5678...
└── StrategyManager: 0x9abc...

🎯 Strategy Contracts:
├── AaveStrategy: 0xdef0... (Weight: 4000 bps)
├── CompoundStrategy: 0x1234... (Weight: 3500 bps)
└── LiquidStakingStrategy: 0x5678... (Weight: 2500 bps)
```

## Contract Verification

### Automatic Verification

Contracts are automatically verified during deployment if `ETHERSCAN_API_KEY` is set.

### Manual Verification

If automatic verification fails:

```bash
# Verify main vault contract
forge verify-contract 0xVAULT_ADDRESS \
    src/AbunfiVault.sol:AbunfiVault \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $(cast abi-encode "constructor(address,address)" 0xUSDC_ADDRESS 0x0000000000000000000000000000000000000000)

# Verify strategy manager
forge verify-contract 0xSTRATEGY_MANAGER_ADDRESS \
    src/StrategyManager.sol:StrategyManager \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

### Verification Status

Check verification status on [Sepolia Etherscan](https://sepolia.etherscan.io/).

## Post-Deployment Testing

### 1. Basic Functionality Test

```bash
# Test deposit functionality
cast send 0xVAULT_ADDRESS \
    "deposit(uint256)" 1000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL

# Check vault balance
cast call 0xVAULT_ADDRESS \
    "totalDeposits()" \
    --rpc-url $SEPOLIA_RPC_URL
```

### 2. Strategy Testing

```bash
# Check strategy allocations
cast call 0xVAULT_ADDRESS \
    "getStrategyAllocations()" \
    --rpc-url $SEPOLIA_RPC_URL

# Test harvest functionality
cast send 0xVAULT_ADDRESS \
    "harvestAll()" \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL
```

### 3. Integration Tests

```bash
# Run integration tests against deployed contracts
SEPOLIA_VAULT_ADDRESS=0xVAULT_ADDRESS forge test --match-contract Integration -vvv
```

## Troubleshooting

### Common Issues

#### 1. Insufficient Gas

```
Error: Transaction failed due to insufficient gas
```

**Solution:** Increase gas limit or gas price in foundry.toml:

```toml
[profile.default]
gas_limit = 3000000
gas_price = 20000000000  # 20 gwei
```

#### 2. Nonce Too Low

```
Error: nonce too low
```

**Solution:** Reset nonce or wait for pending transactions to confirm.

#### 3. Contract Size Too Large

```
Error: Contract code size exceeds limit
```

**Solution:** Enable via-ir optimization:

```toml
[profile.default]
via_ir = true
optimizer_runs = 200
```

#### 4. Verification Failed

```
Error: Contract verification failed
```

**Solutions:**
- Check constructor arguments are correct
- Ensure contract source matches deployed bytecode
- Try manual verification with exact compiler settings

### Getting Help

1. **Check Logs:** Use `-vvvv` flag for detailed logs
2. **Foundry Book:** [https://book.getfoundry.sh/](https://book.getfoundry.sh/)
3. **Discord:** Foundry Discord community
4. **GitHub Issues:** Report bugs in the repository

## Network Configurations

### Supported Networks

| Network | Chain ID | RPC URL | Explorer |
|---------|----------|---------|----------|
| Sepolia | 11155111 | Alchemy/Infura | sepolia.etherscan.io |
| Mainnet | 1 | Alchemy/Infura | etherscan.io |
| Arbitrum | 42161 | Alchemy | arbiscan.io |
| Polygon | 137 | Alchemy | polygonscan.com |

### Network-Specific Notes

#### Sepolia Testnet
- **Purpose:** Primary testnet for production testing
- **Faucet:** [https://sepoliafaucet.com/](https://sepoliafaucet.com/)
- **Block Time:** ~12 seconds
- **Gas Costs:** Very low (test ETH)

#### Ethereum Mainnet
- **Purpose:** Production deployment
- **Gas Costs:** High (real ETH)
- **Security:** Maximum security required
- **Verification:** Essential for transparency

## Security Considerations

### Pre-Deployment

1. **Audit Contracts:** Complete security audit
2. **Test Coverage:** 100% test coverage
3. **Formal Verification:** For critical functions
4. **Multi-sig Setup:** Use multi-sig for ownership

### During Deployment

1. **Private Key Security:** Use hardware wallet for mainnet
2. **Gas Price:** Monitor gas prices for optimal deployment
3. **Verification:** Verify all contracts immediately
4. **Backup:** Save all deployment artifacts

### Post-Deployment

1. **Monitoring:** Set up contract monitoring
2. **Emergency Procedures:** Test pause/emergency functions
3. **Upgrade Path:** Plan for potential upgrades
4. **Documentation:** Maintain deployment documentation

## Maintenance

### Regular Tasks

1. **Monitor Gas Usage:** Track strategy gas costs
2. **Performance Metrics:** Monitor APY and yields
3. **Security Updates:** Keep dependencies updated
4. **Backup Deployments:** Regular deployment backups

### Emergency Procedures

1. **Pause Contracts:** Emergency pause functionality
2. **Withdraw Funds:** Emergency withdrawal procedures
3. **Communication:** User notification procedures
4. **Recovery:** Disaster recovery plans

---

For additional support, please refer to the project documentation or contact the development team.
