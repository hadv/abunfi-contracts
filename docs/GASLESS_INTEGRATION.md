# Abunfi Gasless Transactions Integration Guide

This guide explains how to integrate gasless transactions into your frontend application using the Abunfi gasless infrastructure.

## Overview

The Abunfi gasless system enables users to interact with smart contracts without holding ETH for gas fees. The system sponsors gas costs for users, making DeFi accessible to users in emerging markets.

### Architecture Components

1. **ERC-2771 Meta-Transactions**: Users sign messages instead of transactions
2. **AbunfiRelay**: Forwards meta-transactions and handles gas sponsorship
3. **AbunfiPaymaster**: Manages gas sponsorship funds and limits
4. **AbunfiVault**: Main contract with gasless support

## Quick Start

### 1. Installation

```bash
npm install ethers @openzeppelin/contracts
```

### 2. Contract Addresses

```javascript
// Replace with your deployed contract addresses
const CONTRACTS = {
  vault: "0x...", // AbunfiVault address
  relay: "0x...", // AbunfiRelay address  
  paymaster: "0x...", // AbunfiPaymaster address
  usdc: "0x..." // USDC token address
};
```

### 3. Basic Setup

```javascript
import { ethers } from 'ethers';

// Initialize provider (user doesn't need ETH)
const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();

// Contract ABIs (simplified)
const VAULT_ABI = [
  "function deposit(uint256 amount)",
  "function withdraw(uint256 shares)",
  "function balanceOf(address user) view returns (uint256)",
  "function userShares(address user) view returns (uint256)"
];

const RELAY_ABI = [
  "function executeWithSponsorship((address,address,uint256,uint256,uint48,bytes,bytes))",
  "function canSponsorTransaction((address,address,uint256,uint256,uint48,bytes,bytes)) view returns (bool, string)",
  "function getEstimatedCost((address,address,uint256,uint256,uint48,bytes,bytes)) view returns (uint256)"
];

// Initialize contracts
const vault = new ethers.Contract(CONTRACTS.vault, VAULT_ABI, provider);
const relay = new ethers.Contract(CONTRACTS.relay, RELAY_ABI, provider);
```

## Core Functions

### 1. Create Meta-Transaction

```javascript
async function createMetaTransaction(contractAddress, functionData, gasLimit = 300000) {
  const userAddress = await signer.getAddress();
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  
  const request = {
    from: userAddress,
    to: contractAddress,
    value: 0,
    gas: gasLimit,
    deadline: deadline,
    data: functionData,
    signature: "0x" // Will be filled after signing
  };
  
  return request;
}
```

### 2. Sign Meta-Transaction

```javascript
async function signMetaTransaction(request) {
  // EIP-712 domain for the relay contract
  const domain = {
    name: "AbunfiRelay",
    version: "1",
    chainId: await signer.getChainId(),
    verifyingContract: CONTRACTS.relay
  };
  
  // EIP-712 types for ForwardRequest
  const types = {
    ForwardRequestData: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "gas", type: "uint256" },
      { name: "deadline", type: "uint48" },
      { name: "data", type: "bytes" },
      { name: "signature", type: "bytes" }
    ]
  };
  
  // Create a copy without signature for signing
  const requestToSign = { ...request };
  delete requestToSign.signature;
  
  // Sign the request
  const signature = await signer._signTypedData(domain, types, requestToSign);
  
  // Add signature to request
  request.signature = signature;
  
  return request;
}
```

### 3. Execute Gasless Transaction

```javascript
async function executeGaslessTransaction(request) {
  try {
    // Check if transaction can be sponsored
    const [canSponsor, reason] = await relay.canSponsorTransaction(request);
    
    if (!canSponsor) {
      throw new Error(`Cannot sponsor transaction: ${reason}`);
    }
    
    // Get estimated cost
    const estimatedCost = await relay.getEstimatedCost(request);
    console.log(`Estimated gas cost: ${ethers.utils.formatEther(estimatedCost)} ETH`);
    
    // Execute the transaction through a relayer service
    // In production, this would be sent to your relayer backend
    const response = await fetch('/api/relay', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ request })
    });
    
    const result = await response.json();
    
    if (result.success) {
      console.log('Transaction executed successfully:', result.txHash);
      return result.txHash;
    } else {
      throw new Error(result.error);
    }
    
  } catch (error) {
    console.error('Gasless transaction failed:', error);
    throw error;
  }
}
```

## Example: Gasless Deposit

```javascript
async function gaslessDeposit(amount) {
  try {
    // 1. Prepare the deposit function call
    const depositData = vault.interface.encodeFunctionData("deposit", [amount]);
    
    // 2. Create meta-transaction
    const request = await createMetaTransaction(CONTRACTS.vault, depositData);
    
    // 3. Sign the meta-transaction
    const signedRequest = await signMetaTransaction(request);
    
    // 4. Execute gasless transaction
    const txHash = await executeGaslessTransaction(signedRequest);
    
    console.log('Gasless deposit successful!', txHash);
    return txHash;
    
  } catch (error) {
    console.error('Gasless deposit failed:', error);
    throw error;
  }
}

// Usage
async function handleDeposit() {
  const amount = ethers.utils.parseUnits("100", 6); // 100 USDC
  
  try {
    const txHash = await gaslessDeposit(amount);
    alert(`Deposit successful! Transaction: ${txHash}`);
  } catch (error) {
    alert(`Deposit failed: ${error.message}`);
  }
}
```

## Example: Gasless Withdrawal

```javascript
async function gaslessWithdraw(shares) {
  try {
    // 1. Prepare the withdraw function call
    const withdrawData = vault.interface.encodeFunctionData("withdraw", [shares]);
    
    // 2. Create meta-transaction
    const request = await createMetaTransaction(CONTRACTS.vault, withdrawData);
    
    // 3. Sign the meta-transaction
    const signedRequest = await signMetaTransaction(request);
    
    // 4. Execute gasless transaction
    const txHash = await executeGaslessTransaction(signedRequest);
    
    console.log('Gasless withdrawal successful!', txHash);
    return txHash;
    
  } catch (error) {
    console.error('Gasless withdrawal failed:', error);
    throw error;
  }
}
```

## Backend Relayer Service

You'll need a backend service to relay transactions. Here's a simple Express.js example:

```javascript
// server.js
const express = require('express');
const { ethers } = require('ethers');

const app = express();
app.use(express.json());

// Initialize provider with a funded account for gas
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const relayerWallet = new ethers.Wallet(process.env.RELAYER_PRIVATE_KEY, provider);

const relay = new ethers.Contract(CONTRACTS.relay, RELAY_ABI, relayerWallet);

app.post('/api/relay', async (req, res) => {
  try {
    const { request } = req.body;
    
    // Execute the meta-transaction
    const tx = await relay.executeWithSponsorship(request);
    const receipt = await tx.wait();
    
    res.json({
      success: true,
      txHash: receipt.transactionHash,
      gasUsed: receipt.gasUsed.toString()
    });
    
  } catch (error) {
    console.error('Relay error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.listen(3000, () => {
  console.log('Relayer service running on port 3000');
});
```

## Best Practices

1. **Always check sponsorship availability** before creating transactions
2. **Implement proper error handling** for failed sponsorships
3. **Monitor gas costs** and adjust limits as needed
4. **Use batch transactions** for multiple operations to save gas
5. **Implement rate limiting** in your relayer service
6. **Validate signatures** on the backend before relaying

## Security Considerations

1. **Signature validation**: Always verify signatures before relaying
2. **Nonce management**: Implement proper nonce handling to prevent replay attacks
3. **Gas limits**: Set reasonable gas limits to prevent abuse
4. **Rate limiting**: Implement user-based rate limiting
5. **Monitoring**: Monitor for unusual patterns or potential abuse

## Troubleshooting

### Common Issues

1. **"Gas sponsorship not available"**: User has exceeded daily limits
2. **"Invalid signature"**: Check EIP-712 domain and types
3. **"Insufficient paymaster balance"**: Paymaster needs more ETH
4. **Transaction reverts**: Check contract state and parameters

### Debug Tools

```javascript
// Check user's remaining sponsorship allowance
async function checkUserAllowance(userAddress) {
  const paymaster = new ethers.Contract(CONTRACTS.paymaster, PAYMASTER_ABI, provider);
  const allowance = await paymaster.getUserRemainingAllowance(userAddress);
  console.log(`Remaining allowance: ${ethers.utils.formatEther(allowance)} ETH`);
}

// Check paymaster balance
async function checkPaymasterBalance() {
  const balance = await provider.getBalance(CONTRACTS.paymaster);
  console.log(`Paymaster balance: ${ethers.utils.formatEther(balance)} ETH`);
}
```

This integration enables truly gasless transactions for your users, removing the barrier of needing ETH for gas fees and making DeFi accessible to everyone.

## Complete Frontend Example

See `examples/gasless-frontend/` for a complete React.js example with:
- Wallet connection
- Gasless deposits and withdrawals
- Real-time balance updates
- Transaction status tracking
- Error handling
