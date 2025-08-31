import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';

// Contract addresses - replace with your deployed addresses
const CONTRACTS = {
  vault: "0x...", // AbunfiVault address
  relay: "0x...", // AbunfiRelay address  
  paymaster: "0x...", // AbunfiPaymaster address
  usdc: "0x..." // USDC token address
};

// Simplified ABIs
const VAULT_ABI = [
  "function deposit(uint256 amount)",
  "function withdraw(uint256 shares)",
  "function balanceOf(address user) view returns (uint256)",
  "function userShares(address user) view returns (uint256)",
  "function totalAssets() view returns (uint256)"
];

const USDC_ABI = [
  "function balanceOf(address user) view returns (uint256)",
  "function approve(address spender, uint256 amount)",
  "function allowance(address owner, address spender) view returns (uint256)"
];

const RELAY_ABI = [
  "function executeWithSponsorship((address,address,uint256,uint256,uint48,bytes,bytes))",
  "function canSponsorTransaction((address,address,uint256,uint256,uint48,bytes,bytes)) view returns (bool, string)",
  "function getEstimatedCost((address,address,uint256,uint256,uint48,bytes,bytes)) view returns (uint256)"
];

const PAYMASTER_ABI = [
  "function getUserRemainingAllowance(address user) view returns (uint256)"
];

const GaslessVault = () => {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [userAddress, setUserAddress] = useState('');
  const [contracts, setContracts] = useState({});
  
  // Balances and allowances
  const [usdcBalance, setUsdcBalance] = useState('0');
  const [vaultBalance, setVaultBalance] = useState('0');
  const [userShares, setUserShares] = useState('0');
  const [allowance, setAllowance] = useState('0');
  const [gasAllowance, setGasAllowance] = useState('0');
  
  // Transaction states
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawShares, setWithdrawShares] = useState('');
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState('');

  // Initialize Web3
  useEffect(() => {
    const initWeb3 = async () => {
      if (window.ethereum) {
        const web3Provider = new ethers.providers.Web3Provider(window.ethereum);
        const web3Signer = web3Provider.getSigner();
        
        setProvider(web3Provider);
        setSigner(web3Signer);
        
        // Initialize contracts
        const vault = new ethers.Contract(CONTRACTS.vault, VAULT_ABI, web3Provider);
        const usdc = new ethers.Contract(CONTRACTS.usdc, USDC_ABI, web3Provider);
        const relay = new ethers.Contract(CONTRACTS.relay, RELAY_ABI, web3Provider);
        const paymaster = new ethers.Contract(CONTRACTS.paymaster, PAYMASTER_ABI, web3Provider);
        
        setContracts({ vault, usdc, relay, paymaster });
      }
    };
    
    initWeb3();
  }, []);

  // Connect wallet
  const connectWallet = async () => {
    try {
      await window.ethereum.request({ method: 'eth_requestAccounts' });
      const address = await signer.getAddress();
      setUserAddress(address);
      setStatus('Wallet connected successfully!');
    } catch (error) {
      setStatus(`Failed to connect wallet: ${error.message}`);
    }
  };

  // Load user data
  useEffect(() => {
    if (userAddress && contracts.vault) {
      loadUserData();
    }
  }, [userAddress, contracts]);

  const loadUserData = async () => {
    try {
      const [usdcBal, vaultBal, shares, allowanceAmount, gasAllow] = await Promise.all([
        contracts.usdc.balanceOf(userAddress),
        contracts.vault.balanceOf(userAddress),
        contracts.vault.userShares(userAddress),
        contracts.usdc.allowance(userAddress, CONTRACTS.vault),
        contracts.paymaster.getUserRemainingAllowance(userAddress)
      ]);
      
      setUsdcBalance(ethers.utils.formatUnits(usdcBal, 6));
      setVaultBalance(ethers.utils.formatUnits(vaultBal, 6));
      setUserShares(ethers.utils.formatEther(shares));
      setAllowance(ethers.utils.formatUnits(allowanceAmount, 6));
      setGasAllowance(ethers.utils.formatEther(gasAllow));
    } catch (error) {
      console.error('Failed to load user data:', error);
    }
  };

  // Create and sign meta-transaction
  const createMetaTransaction = async (contractAddress, functionData, gasLimit = 300000) => {
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    
    const request = {
      from: userAddress,
      to: contractAddress,
      value: 0,
      gas: gasLimit,
      deadline: deadline,
      data: functionData,
      signature: "0x"
    };
    
    // EIP-712 domain
    const domain = {
      name: "AbunfiRelay",
      version: "1",
      chainId: await signer.getChainId(),
      verifyingContract: CONTRACTS.relay
    };
    
    // EIP-712 types
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
    
    // Sign the request
    const requestToSign = { ...request };
    delete requestToSign.signature;
    
    const signature = await signer._signTypedData(domain, types, requestToSign);
    request.signature = signature;
    
    return request;
  };

  // Execute gasless transaction
  const executeGaslessTransaction = async (request) => {
    // Check if transaction can be sponsored
    const [canSponsor, reason] = await contracts.relay.canSponsorTransaction(request);
    
    if (!canSponsor) {
      throw new Error(`Cannot sponsor transaction: ${reason}`);
    }
    
    // In a real app, you would send this to your relayer backend
    // For demo purposes, we'll simulate the relayer execution
    setStatus('Executing gasless transaction...');
    
    // Simulate backend call
    const response = await fetch('/api/relay', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ request })
    });
    
    if (!response.ok) {
      throw new Error('Relayer service unavailable');
    }
    
    const result = await response.json();
    
    if (!result.success) {
      throw new Error(result.error);
    }
    
    return result.txHash;
  };

  // Approve USDC spending
  const approveUSDC = async () => {
    try {
      setLoading(true);
      setStatus('Approving USDC spending...');
      
      const tx = await contracts.usdc.connect(signer).approve(
        CONTRACTS.vault, 
        ethers.constants.MaxUint256
      );
      
      await tx.wait();
      setStatus('USDC approval successful!');
      await loadUserData();
    } catch (error) {
      setStatus(`Approval failed: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  // Gasless deposit
  const gaslessDeposit = async () => {
    try {
      setLoading(true);
      setStatus('Creating gasless deposit...');
      
      const amount = ethers.utils.parseUnits(depositAmount, 6);
      const depositData = contracts.vault.interface.encodeFunctionData("deposit", [amount]);
      
      const request = await createMetaTransaction(CONTRACTS.vault, depositData);
      const txHash = await executeGaslessTransaction(request);
      
      setStatus(`Gasless deposit successful! TX: ${txHash}`);
      setDepositAmount('');
      await loadUserData();
    } catch (error) {
      setStatus(`Gasless deposit failed: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  // Gasless withdrawal
  const gaslessWithdraw = async () => {
    try {
      setLoading(true);
      setStatus('Creating gasless withdrawal...');
      
      const shares = ethers.utils.parseEther(withdrawShares);
      const withdrawData = contracts.vault.interface.encodeFunctionData("withdraw", [shares]);
      
      const request = await createMetaTransaction(CONTRACTS.vault, withdrawData);
      const txHash = await executeGaslessTransaction(request);
      
      setStatus(`Gasless withdrawal successful! TX: ${txHash}`);
      setWithdrawShares('');
      await loadUserData();
    } catch (error) {
      setStatus(`Gasless withdrawal failed: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h1 className="text-3xl font-bold text-center mb-8">Abunfi Gasless Vault</h1>
      
      {/* Wallet Connection */}
      {!userAddress ? (
        <div className="text-center">
          <button 
            onClick={connectWallet}
            className="bg-blue-500 text-white px-6 py-3 rounded-lg hover:bg-blue-600"
          >
            Connect Wallet
          </button>
        </div>
      ) : (
        <div>
          {/* User Info */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            <div className="bg-gray-100 p-4 rounded">
              <h3 className="font-semibold">USDC Balance</h3>
              <p className="text-xl">{parseFloat(usdcBalance).toFixed(2)}</p>
            </div>
            <div className="bg-gray-100 p-4 rounded">
              <h3 className="font-semibold">Vault Balance</h3>
              <p className="text-xl">{parseFloat(vaultBalance).toFixed(2)}</p>
            </div>
            <div className="bg-gray-100 p-4 rounded">
              <h3 className="font-semibold">Your Shares</h3>
              <p className="text-xl">{parseFloat(userShares).toFixed(4)}</p>
            </div>
            <div className="bg-gray-100 p-4 rounded">
              <h3 className="font-semibold">Gas Allowance</h3>
              <p className="text-xl">{parseFloat(gasAllowance).toFixed(4)} ETH</p>
            </div>
          </div>

          {/* USDC Approval */}
          {parseFloat(allowance) === 0 && (
            <div className="mb-6 p-4 bg-yellow-100 rounded">
              <p className="mb-4">You need to approve USDC spending first.</p>
              <button 
                onClick={approveUSDC}
                disabled={loading}
                className="bg-yellow-500 text-white px-4 py-2 rounded hover:bg-yellow-600 disabled:opacity-50"
              >
                {loading ? 'Approving...' : 'Approve USDC'}
              </button>
            </div>
          )}

          {/* Deposit Section */}
          <div className="grid md:grid-cols-2 gap-6 mb-8">
            <div className="border p-6 rounded-lg">
              <h2 className="text-xl font-semibold mb-4">Gasless Deposit</h2>
              <input
                type="number"
                placeholder="Amount (USDC)"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="w-full p-3 border rounded mb-4"
              />
              <button
                onClick={gaslessDeposit}
                disabled={loading || !depositAmount || parseFloat(allowance) === 0}
                className="w-full bg-green-500 text-white py-3 rounded hover:bg-green-600 disabled:opacity-50"
              >
                {loading ? 'Processing...' : 'Deposit (Gasless)'}
              </button>
            </div>

            {/* Withdraw Section */}
            <div className="border p-6 rounded-lg">
              <h2 className="text-xl font-semibold mb-4">Gasless Withdraw</h2>
              <input
                type="number"
                placeholder="Shares to withdraw"
                value={withdrawShares}
                onChange={(e) => setWithdrawShares(e.target.value)}
                className="w-full p-3 border rounded mb-4"
              />
              <button
                onClick={gaslessWithdraw}
                disabled={loading || !withdrawShares || parseFloat(userShares) === 0}
                className="w-full bg-red-500 text-white py-3 rounded hover:bg-red-600 disabled:opacity-50"
              >
                {loading ? 'Processing...' : 'Withdraw (Gasless)'}
              </button>
            </div>
          </div>

          {/* Status */}
          {status && (
            <div className="p-4 bg-blue-100 rounded mb-4">
              <p>{status}</p>
            </div>
          )}

          {/* Refresh Button */}
          <div className="text-center">
            <button
              onClick={loadUserData}
              className="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600"
            >
              Refresh Data
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default GaslessVault;
