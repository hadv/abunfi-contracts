# Abunfi Contracts Deployments

This directory contains deployment artifacts and configuration files for Abunfi smart contracts across different networks.

## Directory Structure

```
deployments/
├── README.md                 # This file
├── sepolia-core.json        # Sepolia testnet core contracts
├── sepolia-eip7702.json     # Sepolia EIP-7702 gasless infrastructure
├── mainnet-core.json        # Mainnet core contracts (when deployed)
├── arbitrum-core.json       # Arbitrum deployment (when deployed)
└── polygon-core.json        # Polygon deployment (when deployed)
```

## Deployment Files Format

Each deployment file contains:

```json
{
  "network": "sepolia",
  "chainId": 11155111,
  "deployer": "0x...",
  "timestamp": 1234567890,
  "blockNumber": 12345,
  "contracts": {
    "core": {
      "usdc": "0x...",
      "vault": "0x...",
      "strategyManager": "0x..."
    },
    "strategies": {
      "aave": "0x...",
      "compound": "0x...",
      "liquidStaking": "0x..."
    },
    "mocks": {
      "aavePool": "0x...",
      "compoundComet": "0x..."
    }
  },
  "configuration": {
    "strategyWeights": {
      "aave": 4000,
      "compound": 3500,
      "liquidStaking": 2500
    },
    "riskScores": {
      "aave": 15,
      "compound": 20,
      "liquidStaking": 35
    }
  },
  "testUsers": [
    "0x1234567890123456789012345678901234567890",
    "0x2345678901234567890123456789012345678901"
  ]
}
```

## Network Information

### Sepolia Testnet
- **Chain ID:** 11155111
- **Purpose:** Primary testnet for production testing
- **Explorer:** https://sepolia.etherscan.io/
- **Faucet:** https://sepoliafaucet.com/

### Ethereum Mainnet
- **Chain ID:** 1
- **Purpose:** Production deployment
- **Explorer:** https://etherscan.io/

### Arbitrum One
- **Chain ID:** 42161
- **Purpose:** L2 scaling solution
- **Explorer:** https://arbiscan.io/

### Polygon
- **Chain ID:** 137
- **Purpose:** Alternative L2 solution
- **Explorer:** https://polygonscan.com/

## Usage

### Loading Deployment Data

```javascript
// Node.js
const deployment = require('./deployments/sepolia-core.json');
console.log('Vault address:', deployment.contracts.core.vault);

// Frontend
fetch('./deployments/sepolia-core.json')
  .then(response => response.json())
  .then(deployment => {
    console.log('Contracts:', deployment.contracts);
  });
```

### Contract Interaction

```bash
# Using cast (Foundry)
cast call <VAULT_ADDRESS> "totalDeposits()" --rpc-url $SEPOLIA_RPC_URL

# Using ethers.js
const vault = new ethers.Contract(
  deployment.contracts.core.vault,
  vaultABI,
  provider
);
```

## Verification Status

| Network | Vault | Strategy Manager | Aave Strategy | Compound Strategy | Liquid Staking |
|---------|-------|------------------|---------------|-------------------|----------------|
| Sepolia | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mainnet | ❌ | ❌ | ❌ | ❌ | ❌ |
| Arbitrum | ❌ | ❌ | ❌ | ❌ | ❌ |
| Polygon | ❌ | ❌ | ❌ | ❌ | ❌ |

## Security Notes

1. **Testnet vs Mainnet:** Testnet deployments use mock contracts for external protocols
2. **Private Keys:** Never commit private keys or sensitive data to this directory
3. **Verification:** All mainnet contracts must be verified on Etherscan
4. **Audits:** Mainnet deployments require completed security audits

## Deployment History

### Sepolia Testnet
- **Latest:** [Date] - Core contracts v1.0.0
- **Previous:** [Date] - Initial deployment

### Mainnet
- **Status:** Not deployed yet
- **Planned:** After security audit completion

## Integration

### Frontend Configuration

```typescript
// config/contracts.ts
export const CONTRACTS = {
  [ChainId.SEPOLIA]: {
    vault: '0x...',
    usdc: '0x...',
    strategyManager: '0x...',
  },
  [ChainId.MAINNET]: {
    vault: '0x...',
    usdc: '0xA0b86a33E6441E6C8C7F1C7C8C7F1C7C8C7F1C7C',
    strategyManager: '0x...',
  },
};
```

### Backend Integration

```python
# Python example
import json

def load_deployment(network: str):
    with open(f'deployments/{network}-core.json', 'r') as f:
        return json.load(f)

sepolia_contracts = load_deployment('sepolia')
vault_address = sepolia_contracts['contracts']['core']['vault']
```

## Monitoring

### Contract Health Checks

```bash
# Check vault balance
cast call $VAULT_ADDRESS "totalDeposits()" --rpc-url $RPC_URL

# Check strategy allocations
cast call $VAULT_ADDRESS "getStrategyAllocations()" --rpc-url $RPC_URL

# Check contract owner
cast call $VAULT_ADDRESS "owner()" --rpc-url $RPC_URL
```

### Automated Monitoring

Set up monitoring for:
- Contract balance changes
- Strategy performance
- Gas usage patterns
- Error rates
- Security events

## Backup and Recovery

1. **Regular Backups:** Backup deployment files regularly
2. **Version Control:** All deployment files are version controlled
3. **Recovery Procedures:** Document recovery procedures for each network
4. **Emergency Contacts:** Maintain emergency contact information

## Support

For deployment-related issues:
1. Check the deployment logs
2. Verify contract addresses on block explorer
3. Test contract interactions
4. Contact the development team

---

**Note:** This directory is automatically updated by deployment scripts. Manual edits may be overwritten.
