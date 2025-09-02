# EIP-7702 Gasless Transactions for Abunfi

This guide explains how to implement and use gasless transactions with EIP-7702 account delegation for the Abunfi micro-savings platform.

## Overview

EIP-7702 introduces a revolutionary approach to account abstraction by allowing EOAs (Externally Owned Accounts) to temporarily delegate their execution to smart contract code. This enables gasless transactions without requiring users to deploy new smart accounts.

### Key Benefits

1. **No New Accounts**: Users keep their existing EOAs
2. **Temporary Delegation**: Code delegation can be revoked at any time
3. **Native Support**: Built into the Ethereum protocol (post-Pectra upgrade)
4. **Gas Sponsorship**: Paymasters can sponsor transaction fees
5. **Better UX**: Seamless integration with existing wallets

## Architecture

```
User EOA → EIP-7702 Delegation → Smart Account Logic → Paymaster → Gasless Execution
```

### Components

1. **AbunfiSmartAccount**: Implementation contract that EOAs delegate to
2. **EIP7702Paymaster**: Manages gas sponsorship with sophisticated policies
3. **EIP7702Bundler**: Batches and executes user operations
4. **Frontend SDK**: Easy integration for dApps

## Getting Started

### 1. Deploy the Infrastructure

```bash
# Deploy EIP-7702 contracts
forge script script/DeployEIP7702.s.sol --rpc-url $RPC_URL --broadcast

# The deployment will output contract addresses
```

### 2. User Account Delegation

Users need to create an EIP-7702 delegation transaction:

```javascript
// EIP-7702 delegation transaction
const delegationTx = {
  type: 0x04, // EIP-7702 transaction type
  to: userAddress, // User's EOA
  value: 0,
  data: '0x',
  authorizationList: [{
    chainId: 1, // Current chain ID
    address: smartAccountImplAddress, // Smart account implementation
    nonce: userNonce,
    v: 0, r: '0x', s: '0x' // Signature components
  }]
};

// Sign and send the delegation transaction
const tx = await signer.sendTransaction(delegationTx);
```

### 3. Initialize Delegated Account

After delegation, initialize the account:

```javascript
import EIP7702SDK from './sdk/eip7702-sdk.js';

const sdk = new EIP7702SDK({
  provider: new ethers.providers.Web3Provider(window.ethereum),
  signer: provider.getSigner(),
  smartAccountAddress: "0x...", // Implementation address
  paymasterAddress: "0x...",
  bundlerAddress: "0x...",
  vaultAddress: "0x...",
  bundlerUrl: "https://bundler.abunfi.com"
});

// Initialize the delegated account
const initUserOp = await sdk.initializeDelegatedAccount(userAddress);
await sdk.executeGaslessTransaction(initUserOp);
```

### 4. Execute Gasless Transactions

```javascript
// Gasless deposit
const result = await sdk.gaslessDeposit(ethers.utils.parseUnits("100", 6));
console.log("Gasless deposit successful:", result.txHash);

// Gasless withdrawal
const shares = await vault.userShares(userAddress);
const withdrawResult = await sdk.gaslessWithdraw(shares.div(2)); // Withdraw half
```

## Smart Contract Integration

### AbunfiSmartAccount

The core smart account implementation that EOAs delegate to:

```solidity
// Key functions
function initialize(address owner, address paymaster) external;
function executeUserOperation(UserOperation calldata userOp) external;
function executeBatch(UserOperation[] calldata userOps) external;
function getUserOperationHash(UserOperation calldata userOp) external view returns (bytes32);
```

### EIP7702Paymaster

Manages gas sponsorship with configurable policies:

```solidity
struct SponsorshipPolicy {
    uint256 dailyGasLimit;        // Daily gas limit in wei
    uint256 perTxGasLimit;        // Per-transaction gas limit
    uint256 dailyTxLimit;         // Daily transaction count limit
    bool requiresWhitelist;       // Whitelist requirement
    bool isActive;                // Policy active status
}

// Key functions
function validateUserOperation(UserOperation calldata userOp, UserOperationContext calldata context) external view returns (bool, uint256);
function executeSponsorship(UserOperation calldata userOp, UserOperationContext calldata context, uint256 actualGasUsed) external;
function setAccountPolicy(address account, SponsorshipPolicy calldata policy) external;
```

### EIP7702Bundler

Handles batching and execution of user operations:

```solidity
// Key functions
function executeUserOperation(address account, UserOperation calldata userOp, UserOperationContext calldata context) external returns (ExecutionResult memory);
function executeBatch(address[] calldata accounts, UserOperation[] calldata userOps, UserOperationContext[] calldata contexts) external returns (BatchExecutionResult memory);
function simulateUserOperation(address account, UserOperation calldata userOp) external view returns (bool, uint256, bytes memory);
```

## Frontend Integration

### Complete React Example

```jsx
import React, { useState, useEffect } from 'react';
import EIP7702SDK from '../sdk/eip7702-sdk.js';

const GaslessVault = () => {
  const [sdk, setSdk] = useState(null);
  const [isDelegated, setIsDelegated] = useState(false);
  const [balance, setBalance] = useState('0');

  useEffect(() => {
    const initSDK = async () => {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      
      const sdkInstance = new EIP7702SDK({
        provider,
        signer,
        smartAccountAddress: "0x...",
        paymasterAddress: "0x...",
        bundlerAddress: "0x...",
        vaultAddress: "0x...",
        bundlerUrl: "https://bundler.abunfi.com"
      });
      
      setSdk(sdkInstance);
      
      // Check if account is already delegated
      const delegated = await sdkInstance.isDelegated();
      setIsDelegated(delegated);
    };
    
    initSDK();
  }, []);

  const delegateAccount = async () => {
    const userAddress = await sdk.signer.getAddress();
    const delegationTx = await sdk.createDelegationTransaction(userAddress);
    
    const tx = await sdk.signer.sendTransaction(delegationTx);
    await tx.wait();
    
    // Initialize the delegated account
    const initUserOp = await sdk.initializeDelegatedAccount(userAddress);
    await sdk.executeGaslessTransaction(initUserOp);
    
    setIsDelegated(true);
  };

  const gaslessDeposit = async (amount) => {
    try {
      const result = await sdk.gaslessDeposit(ethers.utils.parseUnits(amount, 6));
      console.log('Deposit successful:', result);
      // Update balance
      await loadBalance();
    } catch (error) {
      console.error('Deposit failed:', error);
    }
  };

  return (
    <div>
      {!isDelegated ? (
        <button onClick={delegateAccount}>
          Enable Gasless Transactions
        </button>
      ) : (
        <div>
          <h3>Balance: {balance} USDC</h3>
          <button onClick={() => gaslessDeposit('100')}>
            Deposit 100 USDC (Gasless)
          </button>
        </div>
      )}
    </div>
  );
};
```

## Backend Bundler Service

Example Express.js bundler service:

```javascript
const express = require('express');
const { ethers } = require('ethers');

const app = express();
app.use(express.json());

// Initialize contracts
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const bundlerWallet = new ethers.Wallet(process.env.BUNDLER_PRIVATE_KEY, provider);
const bundler = new ethers.Contract(BUNDLER_ADDRESS, BUNDLER_ABI, bundlerWallet);

app.post('/api/execute', async (req, res) => {
  try {
    const { account, userOp, context } = req.body;
    
    // Execute the user operation
    const tx = await bundler.executeUserOperation(account, userOp, context);
    const receipt = await tx.wait();
    
    res.json({
      success: true,
      txHash: receipt.transactionHash,
      gasUsed: receipt.gasUsed.toString()
    });
    
  } catch (error) {
    console.error('Execution error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.post('/api/batch', async (req, res) => {
  try {
    const { accounts, userOps, contexts } = req.body;
    
    // Execute batch
    const tx = await bundler.executeBatch(accounts, userOps, contexts);
    const receipt = await tx.wait();
    
    res.json({
      success: true,
      txHash: receipt.transactionHash,
      gasUsed: receipt.gasUsed.toString()
    });
    
  } catch (error) {
    console.error('Batch execution error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.listen(3000, () => {
  console.log('EIP-7702 Bundler service running on port 3000');
});
```

## Security Considerations

### 1. Delegation Security
- Users can revoke delegation at any time
- Delegation is temporary and reversible
- Implementation contract should be immutable

### 2. Paymaster Security
- Implement robust spending limits
- Monitor for unusual patterns
- Use whitelisting for initial launch
- Regular balance monitoring

### 3. Bundler Security
- Validate all user operations
- Implement rate limiting
- Secure private key management
- Monitor for MEV attacks

### 4. Signature Validation
- Always verify user operation signatures
- Implement proper nonce management
- Prevent replay attacks
- Validate authorization lists

## Monitoring and Analytics

### Key Metrics to Track

1. **Gas Sponsorship**
   - Daily gas spending per user
   - Total gas sponsored
   - Average transaction cost

2. **User Adoption**
   - Number of delegated accounts
   - Active users per day
   - Transaction success rate

3. **System Health**
   - Paymaster balance
   - Bundler performance
   - Failed transaction rate

### Alerts to Set Up

- Paymaster balance below threshold
- Unusual gas spending patterns
- High transaction failure rate
- Bundler service downtime

## Troubleshooting

### Common Issues

1. **"Account not delegated"**
   - User needs to send EIP-7702 delegation transaction first

2. **"Gas sponsorship not available"**
   - Check paymaster balance and user limits

3. **"Invalid signature"**
   - Verify user operation hash calculation and signing

4. **"Invalid nonce"**
   - Ensure nonce matches account state

### Debug Tools

```javascript
// Check delegation status
const isDelegated = await sdk.isDelegated();

// Check sponsorship allowance
const allowance = await sdk.getSponsorshipAllowance();

// Simulate operation
const simulation = await bundler.simulateUserOperation(account, userOp);
```

## Conclusion

EIP-7702 provides the most elegant solution for gasless transactions, combining the benefits of account abstraction with the simplicity of keeping existing EOAs. This implementation enables Abunfi to offer truly gasless micro-savings to users in emerging markets, removing the barrier of needing ETH for gas fees.

The system is designed to be secure, scalable, and user-friendly, making DeFi accessible to everyone regardless of their technical knowledge or ETH holdings.
