// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/eip7702/AbunfiSmartAccount.sol";
import "../../src/eip7702/EIP7702Paymaster.sol";
import "../../src/eip7702/EIP7702Bundler.sol";
import "../../src/AbunfiVault.sol";
import "../../src/mocks/MockERC20.sol";

/**
 * @title EIP7702IntegrationTest
 * @dev Comprehensive tests for EIP-7702 gasless transaction system
 */
contract EIP7702IntegrationTest is Test {
    
    AbunfiSmartAccount public smartAccountImpl;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;
    AbunfiVault public vault;
    MockERC20 public usdc;
    
    address public owner = address(0x1001);
    address public user1 = address(0x1002);
    address public user2 = address(0x1003);
    address public bundlerOperator = address(0x1004);
    
    uint256 public user1PrivateKey = 0x12345;
    uint256 public user2PrivateKey = 0x67890;
    
    // Test constants
    uint256 public constant INITIAL_PAYMASTER_FUNDING = 10 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC
    uint256 public constant MINIMUM_DEPOSIT = 4e6; // 4 USDC
    
    event AccountInitialized(address indexed owner, address indexed paymaster);
    event TransactionExecuted(address indexed target, uint256 value, bytes data, bool success);
    event UserOperationSponsored(address indexed account, address indexed actualGasPrice, uint256 actualGasCost, uint256 actualGasUsed);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy implementation contracts
        smartAccountImpl = new AbunfiSmartAccount();
        paymaster = new EIP7702Paymaster();
        bundler = new EIP7702Bundler();
        
        // Deploy USDC and Vault
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // For EIP-7702, we don't need a trusted forwarder
        // The vault will interact directly with delegated EOAs
        vault = new AbunfiVault(address(usdc), address(0));
        
        // Configure system
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);
        
        // Fund paymaster
        vm.deal(address(paymaster), INITIAL_PAYMASTER_FUNDING);
        
        // Setup users
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        
        // Mint USDC to users
        usdc.mint(user1, 1000e6); // 1000 USDC
        usdc.mint(user2, 1000e6); // 1000 USDC
        
        vm.stopPrank();
    }
    
    function testSmartAccountInitialization() public {
        // Simulate EIP-7702 delegation by setting code at user1 address
        vm.etch(user1, address(smartAccountImpl).code);
        
        // Initialize the delegated account
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit AccountInitialized(user1, address(paymaster));
        
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Verify initialization
        assertEq(AbunfiSmartAccount(payable(user1)).getOwner(), user1);
        assertEq(AbunfiSmartAccount(payable(user1)).getPaymaster(), address(paymaster));
        assertEq(AbunfiSmartAccount(payable(user1)).getNonce(), 0);
    }
    
    function testUserOperationExecution() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Approve USDC spending
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        
        // Create user operation for deposit
        bytes memory depositData = abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT);
        
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: depositData,
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Sign the user operation
        bytes32 userOpHash = AbunfiSmartAccount(payable(user1)).getUserOperationHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Create paymaster context
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: userOp.maxFeePerGas,
            gasLimit: userOp.gasLimit,
            signature: ""
        });
        
        // Validate with paymaster
        (bool canSponsor, uint256 gasPrice) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor);
        assertEq(gasPrice, userOp.maxFeePerGas);
        
        // Execute through bundler
        vm.prank(bundlerOperator);
        EIP7702Bundler.ExecutionResult memory result = bundler.executeUserOperation(user1, userOp, context);
        
        assertTrue(result.success);
        assertGt(result.gasUsed, 0);
        
        // Verify deposit was successful
        assertEq(vault.userDeposits(user1), DEPOSIT_AMOUNT);
        assertGt(vault.userShares(user1), 0);
    }
    
    function testBatchExecution() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Approve USDC spending
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        
        // Create multiple user operations
        address[] memory accounts = new address[](2);
        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](2);
        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](2);
        
        // First operation: deposit
        bytes memory depositData = abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT);
        accounts[0] = user1;
        userOps[0] = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: depositData,
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Second operation: another deposit
        accounts[1] = user1;
        userOps[1] = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT / 2),
            nonce: 1,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Sign both operations
        for (uint i = 0; i < userOps.length; i++) {
            bytes32 userOpHash = AbunfiSmartAccount(payable(user1)).getUserOperationHash(userOps[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userOpHash);
            userOps[i].signature = abi.encodePacked(r, s, v);
            
            contexts[i] = EIP7702Paymaster.UserOperationContext({
                account: user1,
                maxFeePerGas: userOps[i].maxFeePerGas,
                gasLimit: userOps[i].gasLimit,
                signature: ""
            });
        }
        
        // Execute batch
        vm.prank(bundlerOperator);
        EIP7702Bundler.BatchExecutionResult memory batchResult = bundler.executeBatch(accounts, userOps, contexts);
        
        // Verify batch execution
        assertEq(batchResult.results.length, 2);
        assertEq(batchResult.successCount, 2);
        assertTrue(batchResult.results[0].success);
        assertTrue(batchResult.results[1].success);
        
        // Verify total deposits
        assertEq(vault.userDeposits(user1), DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2);
    }
    
    function testPaymasterLimits() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Set very low limits for testing
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory restrictivePolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.001 ether, // Very low limit
            perTxGasLimit: 0.0005 ether,
            dailyTxLimit: 1,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, restrictivePolicy);
        
        // Create high-gas operation that should exceed limits
        bytes memory depositData = abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT);
        
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: depositData,
            nonce: 0,
            maxFeePerGas: 100 gwei, // High gas price
            maxPriorityFeePerGas: 10 gwei,
            gasLimit: 500000, // High gas limit
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: userOp.maxFeePerGas,
            gasLimit: userOp.gasLimit,
            signature: ""
        });
        
        // Should fail validation due to limits
        (bool canSponsor, ) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);
    }
    
    function testWhitelistRequirement() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Set policy requiring whitelist
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory whitelistPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: true,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, whitelistPolicy);
        
        // Create user operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT),
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: userOp.maxFeePerGas,
            gasLimit: userOp.gasLimit,
            signature: ""
        });
        
        // Should fail without whitelist
        (bool canSponsor, ) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);
        
        // Whitelist the account
        vm.prank(owner);
        paymaster.setAccountWhitelist(user1, true);
        
        // Should now succeed
        (canSponsor, ) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor);
    }
    
    function testNonceValidation() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Create user operation with wrong nonce
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT),
            nonce: 5, // Wrong nonce (should be 0)
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Sign with wrong nonce
        bytes32 userOpHash = AbunfiSmartAccount(payable(user1)).getUserOperationHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Should revert due to invalid nonce
        vm.expectRevert(AbunfiSmartAccount.InvalidNonce.selector);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).executeUserOperation(userOp);
    }
    
    function testSignatureValidation() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Create user operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT),
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Sign with wrong private key
        bytes32 userOpHash = AbunfiSmartAccount(payable(user1)).getUserOperationHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, userOpHash); // Wrong key
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Should revert due to invalid signature
        vm.expectRevert(AbunfiSmartAccount.InvalidSignature.selector);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).executeUserOperation(userOp);
    }
    
    function testPaymasterFunding() public {
        uint256 initialBalance = address(paymaster).balance;
        
        // Add more funding
        vm.deal(owner, 5 ether);
        vm.prank(owner);
        payable(address(paymaster)).transfer(2 ether);
        
        assertEq(address(paymaster).balance, initialBalance + 2 ether);
        
        // Test withdrawal
        vm.prank(owner);
        paymaster.withdrawFunds(1 ether);
        
        assertEq(address(paymaster).balance, initialBalance + 1 ether);
    }
}
