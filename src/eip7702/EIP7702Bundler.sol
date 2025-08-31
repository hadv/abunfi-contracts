// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AbunfiSmartAccount.sol";
import "./EIP7702Paymaster.sol";

/**
 * @title EIP7702Bundler
 * @dev Bundler service for EIP-7702 user operations
 * Handles batching, validation, and execution of gasless transactions
 */
contract EIP7702Bundler is Ownable, ReentrancyGuard {

    // Events
    event UserOperationExecuted(
        address indexed account,
        bytes32 indexed userOpHash,
        bool success,
        uint256 actualGasUsed
    );
    event BatchExecuted(
        uint256 batchSize,
        uint256 successCount,
        uint256 totalGasUsed
    );
    event PaymasterAdded(address indexed paymaster);
    event PaymasterRemoved(address indexed paymaster);

    // Structs
    struct ExecutionResult {
        bool success;
        uint256 gasUsed;
        bytes returnData;
    }

    struct BatchExecutionResult {
        ExecutionResult[] results;
        uint256 totalGasUsed;
        uint256 successCount;
    }

    // State variables
    mapping(address => bool) public supportedPaymasters;
    mapping(bytes32 => bool) public executedOperations; // Prevent replay attacks
    
    uint256 public constant MAX_BATCH_SIZE = 50;
    uint256 public bundlerFee = 1000; // 10% fee in basis points
    uint256 public constant BASIS_POINTS = 10000;

    modifier onlySupportedPaymaster(address paymaster) {
        require(supportedPaymasters[paymaster], "Unsupported paymaster");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Execute a single user operation
     * @param account The delegated smart account
     * @param userOp The user operation to execute
     * @param paymasterContext Context for paymaster validation
     */
    function executeUserOperation(
        address account,
        AbunfiSmartAccount.UserOperation calldata userOp,
        EIP7702Paymaster.UserOperationContext calldata paymasterContext
    ) external nonReentrant returns (ExecutionResult memory result) {
        
        // Validate the operation hasn't been executed
        bytes32 userOpHash = _getUserOperationHash(account, userOp);
        require(!executedOperations[userOpHash], "Operation already executed");
        
        // Mark as executed to prevent replay
        executedOperations[userOpHash] = true;
        
        // Validate with paymaster if specified
        if (userOp.paymaster != address(0)) {
            require(supportedPaymasters[userOp.paymaster], "Unsupported paymaster");
            
            EIP7702Paymaster paymaster = EIP7702Paymaster(payable(userOp.paymaster));
            (bool canSponsor, ) = paymaster.validateUserOperation(userOp, paymasterContext);
            require(canSponsor, "Paymaster validation failed");
        }
        
        // Execute the operation
        uint256 gasStart = gasleft();
        
        try AbunfiSmartAccount(payable(account)).executeUserOperation(userOp) {
            result.success = true;
        } catch (bytes memory reason) {
            result.success = false;
            result.returnData = reason;
        }
        
        result.gasUsed = gasStart - gasleft();
        
        // Handle paymaster sponsorship
        if (userOp.paymaster != address(0) && result.success) {
            EIP7702Paymaster paymaster = EIP7702Paymaster(payable(userOp.paymaster));
            paymaster.executeSponsorship(userOp, paymasterContext, result.gasUsed);
        }
        
        emit UserOperationExecuted(account, userOpHash, result.success, result.gasUsed);
        
        return result;
    }

    /**
     * @dev Execute multiple user operations in a batch
     * @param accounts Array of delegated smart accounts
     * @param userOps Array of user operations
     * @param paymasterContexts Array of paymaster contexts
     */
    function executeBatch(
        address[] calldata accounts,
        AbunfiSmartAccount.UserOperation[] calldata userOps,
        EIP7702Paymaster.UserOperationContext[] calldata paymasterContexts
    ) external nonReentrant returns (BatchExecutionResult memory batchResult) {
        
        require(accounts.length == userOps.length, "Array length mismatch");
        require(userOps.length == paymasterContexts.length, "Array length mismatch");
        require(userOps.length <= MAX_BATCH_SIZE, "Batch too large");
        require(userOps.length > 0, "Empty batch");
        
        batchResult.results = new ExecutionResult[](userOps.length);
        batchResult.successCount = 0;
        batchResult.totalGasUsed = 0;
        
        // Execute each operation
        for (uint256 i = 0; i < userOps.length; i++) {
            // Validate operation hasn't been executed
            bytes32 userOpHash = _getUserOperationHash(accounts[i], userOps[i]);
            
            if (executedOperations[userOpHash]) {
                batchResult.results[i] = ExecutionResult({
                    success: false,
                    gasUsed: 0,
                    returnData: "Operation already executed"
                });
                continue;
            }
            
            // Mark as executed
            executedOperations[userOpHash] = true;
            
            // Validate with paymaster if specified
            if (userOps[i].paymaster != address(0)) {
                if (!supportedPaymasters[userOps[i].paymaster]) {
                    batchResult.results[i] = ExecutionResult({
                        success: false,
                        gasUsed: 0,
                        returnData: "Unsupported paymaster"
                    });
                    continue;
                }

                EIP7702Paymaster paymaster = EIP7702Paymaster(payable(userOps[i].paymaster));
                (bool canSponsor, ) = paymaster.validateUserOperation(userOps[i], paymasterContexts[i]);
                
                if (!canSponsor) {
                    batchResult.results[i] = ExecutionResult({
                        success: false,
                        gasUsed: 0,
                        returnData: "Paymaster validation failed"
                    });
                    continue;
                }
            }
            
            // Execute the operation
            uint256 gasStart = gasleft();
            
            try AbunfiSmartAccount(payable(accounts[i])).executeUserOperation(userOps[i]) {
                batchResult.results[i].success = true;
                batchResult.successCount++;
            } catch (bytes memory reason) {
                batchResult.results[i].success = false;
                batchResult.results[i].returnData = reason;
            }
            
            batchResult.results[i].gasUsed = gasStart - gasleft();
            batchResult.totalGasUsed += batchResult.results[i].gasUsed;
            
            emit UserOperationExecuted(
                accounts[i], 
                userOpHash, 
                batchResult.results[i].success, 
                batchResult.results[i].gasUsed
            );
        }
        
        // Handle batch paymaster sponsorship
        _handleBatchSponsorship(userOps, paymasterContexts, batchResult);
        
        emit BatchExecuted(userOps.length, batchResult.successCount, batchResult.totalGasUsed);
        
        return batchResult;
    }

    /**
     * @dev Handle paymaster sponsorship for batch operations
     */
    function _handleBatchSponsorship(
        AbunfiSmartAccount.UserOperation[] calldata userOps,
        EIP7702Paymaster.UserOperationContext[] calldata paymasterContexts,
        BatchExecutionResult memory batchResult
    ) internal {
        // Handle sponsorship for each successful operation
        for (uint256 i = 0; i < userOps.length; i++) {
            if (batchResult.results[i].success && userOps[i].paymaster != address(0)) {
                EIP7702Paymaster paymaster = EIP7702Paymaster(payable(userOps[i].paymaster));
                paymaster.executeSponsorship(
                    userOps[i],
                    paymasterContexts[i],
                    batchResult.results[i].gasUsed
                );
            }
        }
    }

    /**
     * @dev Simulate user operation execution (for gas estimation)
     * @param account The delegated smart account
     * @param userOp The user operation to simulate
     */
    function simulateUserOperation(
        address account,
        AbunfiSmartAccount.UserOperation calldata userOp
    ) external view returns (bool success, uint256 gasUsed, bytes memory returnData) {
        
        // This would typically be done off-chain or with a simulation framework
        // For now, we'll return estimated values
        
        // Basic validation
        AbunfiSmartAccount smartAccount = AbunfiSmartAccount(payable(account));
        
        // Check if signature would be valid
        if (!smartAccount.isValidSignature(userOp)) {
            return (false, 0, "Invalid signature");
        }
        
        // Check nonce
        if (userOp.nonce != smartAccount.getNonce()) {
            return (false, 0, "Invalid nonce");
        }
        
        // Estimate gas (simplified)
        uint256 estimatedGas = userOp.gasLimit;
        
        return (true, estimatedGas, "");
    }

    /**
     * @dev Get user operation hash
     */
    function getUserOperationHash(
        address account,
        AbunfiSmartAccount.UserOperation calldata userOp
    ) external view returns (bytes32) {
        return _getUserOperationHash(account, userOp);
    }

    /**
     * @dev Check if operation has been executed
     */
    function isOperationExecuted(bytes32 userOpHash) external view returns (bool) {
        return executedOperations[userOpHash];
    }

    // Admin functions
    
    /**
     * @dev Add supported paymaster
     */
    function addPaymaster(address paymaster) external onlyOwner {
        supportedPaymasters[paymaster] = true;
        emit PaymasterAdded(paymaster);
    }

    /**
     * @dev Remove supported paymaster
     */
    function removePaymaster(address paymaster) external onlyOwner {
        supportedPaymasters[paymaster] = false;
        emit PaymasterRemoved(paymaster);
    }

    /**
     * @dev Set bundler fee
     */
    function setBundlerFee(uint256 _bundlerFee) external onlyOwner {
        require(_bundlerFee <= 2000, "Fee too high"); // Max 20%
        bundlerFee = _bundlerFee;
    }

    /**
     * @dev Emergency withdraw
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    // Internal functions
    
    function _getUserOperationHash(
        address account,
        AbunfiSmartAccount.UserOperation calldata userOp
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            account,
            userOp.target,
            userOp.value,
            keccak256(userOp.data),
            userOp.nonce,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            userOp.gasLimit,
            userOp.paymaster,
            keccak256(userOp.paymasterData),
            block.chainid,
            address(this)
        ));
    }

    // Receive ETH for operations
    receive() external payable {}
}
