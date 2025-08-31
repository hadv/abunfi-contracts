// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AbunfiSmartAccount
 * @dev Smart account implementation for EIP-7702 delegation
 * This contract becomes the "code" that EOAs delegate to via EIP-7702
 * Enables gasless transactions through paymaster integration
 */
contract AbunfiSmartAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    // EIP-7702 specific storage slots to avoid conflicts
    // These slots are reserved for EIP-7702 delegation data
    bytes32 private constant OWNER_SLOT = keccak256("eip7702.abunfi.owner");
    bytes32 private constant NONCE_SLOT = keccak256("eip7702.abunfi.nonce");
    bytes32 private constant PAYMASTER_SLOT = keccak256("eip7702.abunfi.paymaster");

    // Events
    event AccountInitialized(address indexed owner, address indexed paymaster);
    event TransactionExecuted(address indexed target, uint256 value, bytes data, bool success);
    event PaymasterUpdated(address indexed oldPaymaster, address indexed newPaymaster);
    event NonceIncremented(address indexed account, uint256 newNonce);

    // Errors
    error InvalidSignature();
    error InvalidNonce();
    error TransactionFailed();
    error OnlyOwner();
    error OnlyPaymaster();
    error InvalidPaymaster();

    // Structs
    struct UserOperation {
        address target;           // Target contract to call
        uint256 value;           // ETH value to send
        bytes data;              // Call data
        uint256 nonce;           // Account nonce
        uint256 maxFeePerGas;    // Maximum fee per gas
        uint256 maxPriorityFeePerGas; // Maximum priority fee per gas
        uint256 gasLimit;        // Gas limit for the operation
        address paymaster;       // Paymaster address (can be zero)
        bytes paymasterData;     // Paymaster-specific data
        bytes signature;         // User signature
    }

    /**
     * @dev Initialize the smart account (called once when EOA delegates)
     * @param owner The EOA that owns this account
     * @param paymaster The paymaster contract for gas sponsorship
     */
    function initialize(address owner, address paymaster) external {
        require(_getOwner() == address(0), "Already initialized");
        require(owner != address(0), "Invalid owner");
        
        _setOwner(owner);
        _setPaymaster(paymaster);
        _setNonce(0);
        
        emit AccountInitialized(owner, paymaster);
    }

    /**
     * @dev Execute a user operation with gas sponsorship
     * @param userOp The user operation to execute
     */
    function executeUserOperation(UserOperation calldata userOp) external {
        address paymaster = _getPaymaster();
        address owner = _getOwner();

        // Allow owner, paymaster, or any caller if the signature is valid
        bool isAuthorized = msg.sender == paymaster ||
                           msg.sender == owner ||
                           _isValidUserOperation(userOp);

        require(isAuthorized, "Unauthorized");
        
        // Validate nonce
        uint256 currentNonce = _getNonce();
        if (userOp.nonce != currentNonce) {
            revert InvalidNonce();
        }
        
        // Validate signature
        bytes32 userOpHash = _getUserOperationHash(userOp);
        address signer = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
        if (signer != _getOwner()) {
            revert InvalidSignature();
        }
        
        // Increment nonce
        _setNonce(currentNonce + 1);
        emit NonceIncremented(address(this), currentNonce + 1);
        
        // Execute the operation
        (bool success, ) = userOp.target.call{value: userOp.value}(userOp.data);
        
        emit TransactionExecuted(userOp.target, userOp.value, userOp.data, success);
        
        if (!success) {
            revert TransactionFailed();
        }
    }

    /**
     * @dev Execute multiple operations in a batch
     * @param userOps Array of user operations to execute
     */
    function executeBatch(UserOperation[] calldata userOps) external {
        address paymaster = _getPaymaster();
        address owner = _getOwner();

        // Allow owner, paymaster, or any caller if all signatures are valid
        bool isAuthorized = msg.sender == paymaster || msg.sender == owner;

        if (!isAuthorized) {
            // Check if all user operations have valid signatures
            isAuthorized = true;
            for (uint256 i = 0; i < userOps.length; i++) {
                if (!_isValidUserOperation(userOps[i])) {
                    isAuthorized = false;
                    break;
                }
            }
        }

        require(isAuthorized, "Unauthorized");
        
        uint256 currentNonce = _getNonce();
        
        for (uint256 i = 0; i < userOps.length; i++) {
            UserOperation calldata userOp = userOps[i];
            
            // Validate nonce (should be sequential)
            if (userOp.nonce != currentNonce + i) {
                revert InvalidNonce();
            }
            
            // Validate signature
            bytes32 userOpHash = _getUserOperationHash(userOp);
            address signer = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
            if (signer != _getOwner()) {
                revert InvalidSignature();
            }
            
            // Execute the operation
            (bool success, ) = userOp.target.call{value: userOp.value}(userOp.data);
            
            emit TransactionExecuted(userOp.target, userOp.value, userOp.data, success);
            
            if (!success) {
                revert TransactionFailed();
            }
        }
        
        // Update nonce after all operations
        _setNonce(currentNonce + userOps.length);
        emit NonceIncremented(address(this), currentNonce + userOps.length);
    }

    /**
     * @dev Simple execute function for direct calls (non-gasless)
     * @param target Target contract
     * @param value ETH value
     * @param data Call data
     */
    function execute(address target, uint256 value, bytes calldata data) external {
        require(msg.sender == _getOwner(), "Only owner");
        
        (bool success, ) = target.call{value: value}(data);
        
        emit TransactionExecuted(target, value, data, success);
        
        if (!success) {
            revert TransactionFailed();
        }
    }

    /**
     * @dev Update the paymaster (only owner)
     * @param newPaymaster New paymaster address
     */
    function setPaymaster(address newPaymaster) external {
        require(msg.sender == _getOwner(), "Only owner");
        
        address oldPaymaster = _getPaymaster();
        _setPaymaster(newPaymaster);
        
        emit PaymasterUpdated(oldPaymaster, newPaymaster);
    }

    /**
     * @dev Get the hash of a user operation for signing
     * @param userOp The user operation
     * @return The hash to be signed
     */
    function getUserOperationHash(UserOperation calldata userOp) external view returns (bytes32) {
        return _getUserOperationHash(userOp);
    }

    /**
     * @dev Check if a signature is valid for a user operation
     * @param userOp The user operation
     * @return True if signature is valid
     */
    function isValidSignature(UserOperation calldata userOp) external view returns (bool) {
        bytes32 userOpHash = _getUserOperationHash(userOp);
        address signer = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
        return signer == _getOwner();
    }

    // View functions
    function getOwner() external view returns (address) {
        return _getOwner();
    }

    function getNonce() external view returns (uint256) {
        return _getNonce();
    }

    function getPaymaster() external view returns (address) {
        return _getPaymaster();
    }

    // Internal functions
    function _isValidUserOperation(UserOperation calldata userOp) internal view returns (bool) {
        // Validate nonce
        if (userOp.nonce != _getNonce()) {
            return false;
        }

        // Validate signature
        bytes32 userOpHash = _getUserOperationHash(userOp);
        address signer = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
        return signer == _getOwner();
    }

    function _getUserOperationHash(UserOperation calldata userOp) internal view returns (bytes32) {
        return keccak256(abi.encode(
            userOp.target,
            userOp.value,
            keccak256(userOp.data),
            userOp.nonce,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            userOp.gasLimit,
            userOp.paymaster,
            keccak256(userOp.paymasterData),
            _getOwner(), // Use owner address instead of contract address
            block.chainid
        ));
    }

    function _getOwner() internal view returns (address) {
        bytes32 slot = OWNER_SLOT;
        address owner;
        assembly {
            owner := sload(slot)
        }
        return owner;
    }

    function _setOwner(address owner) internal {
        bytes32 slot = OWNER_SLOT;
        assembly {
            sstore(slot, owner)
        }
    }

    function _getNonce() internal view returns (uint256) {
        bytes32 slot = NONCE_SLOT;
        uint256 nonce;
        assembly {
            nonce := sload(slot)
        }
        return nonce;
    }

    function _setNonce(uint256 nonce) internal {
        bytes32 slot = NONCE_SLOT;
        assembly {
            sstore(slot, nonce)
        }
    }

    function _getPaymaster() internal view returns (address) {
        bytes32 slot = PAYMASTER_SLOT;
        address paymaster;
        assembly {
            paymaster := sload(slot)
        }
        return paymaster;
    }

    function _setPaymaster(address paymaster) internal {
        bytes32 slot = PAYMASTER_SLOT;
        assembly {
            sstore(slot, paymaster)
        }
    }

    // Fallback and receive functions
    receive() external payable {}
    
    fallback() external payable {
        // Allow the account to receive calls and ETH
    }
}
