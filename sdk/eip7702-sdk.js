/**
 * EIP-7702 Gasless Transaction SDK for Abunfi
 * 
 * This SDK provides easy-to-use functions for creating and executing
 * gasless transactions using EIP-7702 account delegation.
 */

import { ethers } from 'ethers';

// Contract ABIs (simplified for SDK)
const SMART_ACCOUNT_ABI = [
  "function initialize(address owner, address paymaster)",
  "function executeUserOperation((address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes))",
  "function executeBatch((address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes)[])",
  "function getUserOperationHash((address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes)) view returns (bytes32)",
  "function isValidSignature((address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes)) view returns (bool)",
  "function getOwner() view returns (address)",
  "function getNonce() view returns (uint256)",
  "function getPaymaster() view returns (address)"
];

const PAYMASTER_ABI = [
  "function validateUserOperation((address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes),(address,uint256,uint256,bytes)) view returns (bool, uint256)",
  "function getRemainingDailyAllowance(address) view returns (uint256, uint256)",
  "function getEffectivePolicy(address) view returns ((uint256,uint256,uint256,bool,bool))"
];

const BUNDLER_ABI = [
  "function executeUserOperation(address,(address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes),(address,uint256,uint256,bytes))",
  "function executeBatch(address[],(address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes)[],(address,uint256,uint256,bytes)[])",
  "function simulateUserOperation(address,(address,uint256,bytes,uint256,uint256,uint256,uint256,address,bytes,bytes)) view returns (bool, uint256, bytes)"
];

const VAULT_ABI = [
  "function deposit(uint256 amount)",
  "function withdraw(uint256 shares)",
  "function balanceOf(address user) view returns (uint256)",
  "function userShares(address user) view returns (uint256)"
];

class EIP7702SDK {
  constructor(config) {
    this.provider = config.provider;
    this.signer = config.signer;
    this.contracts = {
      smartAccount: config.smartAccountAddress,
      paymaster: config.paymasterAddress,
      bundler: config.bundlerAddress,
      vault: config.vaultAddress
    };
    this.bundlerUrl = config.bundlerUrl || 'http://localhost:3000';
    
    // Initialize contract instances
    this.smartAccountContract = new ethers.Contract(
      this.contracts.smartAccount, 
      SMART_ACCOUNT_ABI, 
      this.provider
    );
    
    this.paymasterContract = new ethers.Contract(
      this.contracts.paymaster, 
      PAYMASTER_ABI, 
      this.provider
    );
    
    this.bundlerContract = new ethers.Contract(
      this.contracts.bundler, 
      BUNDLER_ABI, 
      this.provider
    );
    
    this.vaultContract = new ethers.Contract(
      this.contracts.vault, 
      VAULT_ABI, 
      this.provider
    );
  }

  /**
   * Create an EIP-7702 delegation transaction
   * This allows the user's EOA to delegate to the smart account implementation
   */
  async createDelegationTransaction(userAddress) {
    // EIP-7702 transaction structure
    const delegationTx = {
      type: 0x04, // EIP-7702 transaction type
      to: userAddress, // User's EOA
      value: 0,
      data: '0x',
      authorizationList: [{
        chainId: await this.signer.getChainId(),
        address: this.contracts.smartAccount, // Smart account implementation
        nonce: await this.provider.getTransactionCount(userAddress),
        v: 0, // Will be filled after signing
        r: '0x', // Will be filled after signing
        s: '0x'  // Will be filled after signing
      }]
    };

    // Sign the authorization
    const authHash = this._getAuthorizationHash(delegationTx.authorizationList[0]);
    const signature = await this.signer.signMessage(ethers.utils.arrayify(authHash));
    const sig = ethers.utils.splitSignature(signature);
    
    delegationTx.authorizationList[0].v = sig.v;
    delegationTx.authorizationList[0].r = sig.r;
    delegationTx.authorizationList[0].s = sig.s;

    return delegationTx;
  }

  /**
   * Initialize the delegated account
   */
  async initializeDelegatedAccount(userAddress, paymasterAddress = null) {
    const paymaster = paymasterAddress || this.contracts.paymaster;
    
    // Create initialization call
    const initData = this.smartAccountContract.interface.encodeFunctionData(
      "initialize", 
      [userAddress, paymaster]
    );

    // Create user operation for initialization
    const userOp = await this.createUserOperation({
      target: userAddress, // The delegated account (user's EOA)
      value: 0,
      data: initData,
      paymaster: paymaster
    });

    return userOp;
  }

  /**
   * Create a user operation for gasless execution
   */
  async createUserOperation(params) {
    const {
      target,
      value = 0,
      data,
      gasLimit = 300000,
      maxFeePerGas = null,
      maxPriorityFeePerGas = null,
      paymaster = this.contracts.paymaster,
      paymasterData = '0x'
    } = params;

    const userAddress = await this.signer.getAddress();
    const nonce = await this.smartAccountContract.getNonce();
    
    // Get current gas prices if not provided
    const feeData = await this.provider.getFeeData();
    const finalMaxFeePerGas = maxFeePerGas || feeData.maxFeePerGas;
    const finalMaxPriorityFeePerGas = maxPriorityFeePerGas || feeData.maxPriorityFeePerGas;

    const userOp = {
      target,
      value,
      data,
      nonce,
      maxFeePerGas: finalMaxFeePerGas,
      maxPriorityFeePerGas: finalMaxPriorityFeePerGas,
      gasLimit,
      paymaster,
      paymasterData,
      signature: '0x' // Will be filled after signing
    };

    return userOp;
  }

  /**
   * Sign a user operation
   */
  async signUserOperation(userOp) {
    const userAddress = await this.signer.getAddress();
    
    // Get the hash to sign
    const userOpHash = await this.smartAccountContract.getUserOperationHash(userOp);
    
    // Sign the hash
    const signature = await this.signer.signMessage(ethers.utils.arrayify(userOpHash));
    
    // Add signature to user operation
    userOp.signature = signature;
    
    return userOp;
  }

  /**
   * Execute a gasless transaction
   */
  async executeGaslessTransaction(userOp) {
    // Validate with paymaster first
    const userAddress = await this.signer.getAddress();
    const context = {
      account: userAddress,
      maxFeePerGas: userOp.maxFeePerGas,
      gasLimit: userOp.gasLimit,
      signature: '0x'
    };

    const [canSponsor, gasPrice] = await this.paymasterContract.validateUserOperation(userOp, context);
    
    if (!canSponsor) {
      throw new Error('Transaction cannot be sponsored by paymaster');
    }

    // Send to bundler service
    const response = await fetch(`${this.bundlerUrl}/api/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        account: userAddress,
        userOp,
        context
      })
    });

    if (!response.ok) {
      throw new Error(`Bundler error: ${response.statusText}`);
    }

    const result = await response.json();
    
    if (!result.success) {
      throw new Error(`Execution failed: ${result.error}`);
    }

    return result;
  }

  /**
   * Create and execute a gasless deposit
   */
  async gaslessDeposit(amount) {
    // Create deposit call data
    const depositData = this.vaultContract.interface.encodeFunctionData("deposit", [amount]);
    
    // Create user operation
    const userOp = await this.createUserOperation({
      target: this.contracts.vault,
      data: depositData
    });

    // Sign the operation
    const signedUserOp = await this.signUserOperation(userOp);

    // Execute gaslessly
    return await this.executeGaslessTransaction(signedUserOp);
  }

  /**
   * Create and execute a gasless withdrawal
   */
  async gaslessWithdraw(shares) {
    // Create withdraw call data
    const withdrawData = this.vaultContract.interface.encodeFunctionData("withdraw", [shares]);
    
    // Create user operation
    const userOp = await this.createUserOperation({
      target: this.contracts.vault,
      data: withdrawData
    });

    // Sign the operation
    const signedUserOp = await this.signUserOperation(userOp);

    // Execute gaslessly
    return await this.executeGaslessTransaction(signedUserOp);
  }

  /**
   * Execute multiple operations in a batch
   */
  async executeBatch(operations) {
    const userOps = [];
    
    for (const op of operations) {
      const userOp = await this.createUserOperation(op);
      const signedUserOp = await this.signUserOperation(userOp);
      userOps.push(signedUserOp);
    }

    // Send batch to bundler
    const userAddress = await this.signer.getAddress();
    const contexts = userOps.map(userOp => ({
      account: userAddress,
      maxFeePerGas: userOp.maxFeePerGas,
      gasLimit: userOp.gasLimit,
      signature: '0x'
    }));

    const response = await fetch(`${this.bundlerUrl}/api/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        accounts: userOps.map(() => userAddress),
        userOps,
        contexts
      })
    });

    if (!response.ok) {
      throw new Error(`Batch execution failed: ${response.statusText}`);
    }

    return await response.json();
  }

  /**
   * Get user's sponsorship allowance
   */
  async getSponsorshipAllowance() {
    const userAddress = await this.signer.getAddress();
    const [gasAllowance, txAllowance] = await this.paymasterContract.getRemainingDailyAllowance(userAddress);
    
    return {
      gasAllowance: ethers.utils.formatEther(gasAllowance),
      txAllowance: txAllowance.toString()
    };
  }

  /**
   * Check if account is delegated
   */
  async isDelegated() {
    const userAddress = await this.signer.getAddress();
    const code = await this.provider.getCode(userAddress);
    
    // If the account has code, it's delegated
    return code !== '0x';
  }

  /**
   * Get account nonce
   */
  async getNonce() {
    return await this.smartAccountContract.getNonce();
  }

  // Internal helper functions
  
  _getAuthorizationHash(authorization) {
    return ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'address', 'uint256'],
      [authorization.chainId, authorization.address, authorization.nonce]
    ));
  }
}

// Export for use in frontend applications
export default EIP7702SDK;

// Example usage:
/*
const sdk = new EIP7702SDK({
  provider: new ethers.providers.Web3Provider(window.ethereum),
  signer: provider.getSigner(),
  smartAccountAddress: "0x...",
  paymasterAddress: "0x...",
  bundlerAddress: "0x...",
  vaultAddress: "0x...",
  bundlerUrl: "https://bundler.abunfi.com"
});

// Delegate account (one-time setup)
const delegationTx = await sdk.createDelegationTransaction(userAddress);
await signer.sendTransaction(delegationTx);

// Initialize delegated account
const initUserOp = await sdk.initializeDelegatedAccount(userAddress);
await sdk.executeGaslessTransaction(initUserOp);

// Make gasless deposit
const result = await sdk.gaslessDeposit(ethers.utils.parseUnits("100", 6));
console.log("Gasless deposit successful:", result);
*/
