// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/eip7702/AbunfiSmartAccount.sol";
import "../../src/eip7702/EIP7702Paymaster.sol";
import "../../src/eip7702/EIP7702Bundler.sol";
import "../../src/AbunfiVault.sol";
import "../../src/mocks/MockERC20.sol";

/**
 * @title VaultGaslessIntegrationTest
 * @dev Comprehensive test showing real gasless vault interactions using EIP-7702
 */
contract VaultGaslessIntegrationTest is Test {
    
    AbunfiSmartAccount public smartAccountImpl;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;
    AbunfiVault public vault;
    MockERC20 public usdc;
    
    address public owner = address(0x1001);
    address public user1;
    address public user2;
    address public relayer = address(0x1004);
    
    uint256 public user1PrivateKey = 0x12345;
    uint256 public user2PrivateKey = 0x67890;
    
    // Test constants
    uint256 public constant INITIAL_PAYMASTER_FUNDING = 10 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC
    uint256 public constant INITIAL_USDC_BALANCE = 1000e6; // 1000 USDC
    
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event UserOperationSponsored(address indexed account, address indexed actualGasPrice, uint256 actualGasCost, uint256 actualGasUsed);
    
    function setUp() public {
        // Set user addresses based on private keys
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        
        vm.startPrank(owner);
        
        // Deploy infrastructure
        smartAccountImpl = new AbunfiSmartAccount();
        paymaster = new EIP7702Paymaster();
        bundler = new EIP7702Bundler();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy vault with ERC-2771 support (using address(0) for now, but we'll use bundler for gasless)
        vault = new AbunfiVault(address(usdc), address(0));
        
        // Configure system
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);
        
        // Fund paymaster
        vm.deal(address(paymaster), INITIAL_PAYMASTER_FUNDING);
        
        // Setup users with USDC
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        usdc.mint(user1, INITIAL_USDC_BALANCE);
        usdc.mint(user2, INITIAL_USDC_BALANCE);
        
        vm.stopPrank();
    }
    
    function testGaslessVaultDeposit() public {
        // Step 1: Simulate EIP-7702 delegation by setting code at user1 address
        vm.etch(user1, address(smartAccountImpl).code);
        
        // Step 2: Initialize the delegated account
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Step 3: User approves vault to spend USDC
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        
        // Step 4: Create gasless deposit user operation
        bytes memory depositCalldata = abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT);
        
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: depositCalldata,
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Step 5: Sign the user operation
        bytes32 userOpHash = AbunfiSmartAccount(payable(user1)).getUserOperationHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Step 6: Create paymaster context
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: userOp.maxFeePerGas,
            gasLimit: userOp.gasLimit,
            signature: ""
        });
        
        // Step 7: Validate with paymaster
        (bool canSponsor, uint256 gasPrice) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor, "Paymaster should sponsor the transaction");
        assertEq(gasPrice, userOp.maxFeePerGas);
        
        // Step 8: Check initial state
        assertEq(vault.userDeposits(user1), 0, "Initial deposit should be 0");
        assertEq(vault.userShares(user1), 0, "Initial shares should be 0");
        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should have no USDC initially");
        
        // Step 9: Execute gasless transaction through bundler
        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT * 1e18 / 1e6); // Expected shares calculation
        
        EIP7702Bundler.ExecutionResult memory result = bundler.executeUserOperation(user1, userOp, context);
        
        // Step 10: Verify transaction success
        assertTrue(result.success, "Gasless deposit should succeed");
        assertGt(result.gasUsed, 0, "Gas should be consumed");
        
        // Step 11: Verify vault state changes
        assertEq(vault.userDeposits(user1), DEPOSIT_AMOUNT, "User deposit should be recorded");
        assertGt(vault.userShares(user1), 0, "User should receive shares");
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Vault should hold the deposited USDC");
        assertEq(usdc.balanceOf(user1), INITIAL_USDC_BALANCE - DEPOSIT_AMOUNT, "User USDC balance should decrease");
    }
    
    function testGaslessVaultWithdrawal() public {
        // Setup: First make a regular deposit to have shares to withdraw
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT);
        
        uint256 userShares = vault.userShares(user1);
        uint256 withdrawShares = userShares / 2; // Withdraw half
        
        // Create gasless withdrawal user operation
        bytes memory withdrawCalldata = abi.encodeWithSelector(vault.withdraw.selector, withdrawShares);
        
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: withdrawCalldata,
            nonce: 0, // Reset nonce for this test
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
        
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: userOp.maxFeePerGas,
            gasLimit: userOp.gasLimit,
            signature: ""
        });
        
        uint256 initialUSDCBalance = usdc.balanceOf(user1);
        
        // Execute gasless withdrawal
        vm.prank(relayer);
        EIP7702Bundler.ExecutionResult memory result = bundler.executeUserOperation(user1, userOp, context);
        
        // Verify withdrawal success
        assertTrue(result.success, "Gasless withdrawal should succeed");
        assertEq(vault.userShares(user1), userShares - withdrawShares, "User shares should decrease");
        assertGt(usdc.balanceOf(user1), initialUSDCBalance, "User should receive USDC back");
    }
    
    function testGaslessVaultBatchOperations() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        
        // Create batch operations: two deposits
        address[] memory accounts = new address[](2);
        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](2);
        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](2);
        
        // First deposit
        accounts[0] = user1;
        userOps[0] = AbunfiSmartAccount.UserOperation({
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
        
        // Second deposit
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
        
        // Execute batch gasless transactions
        vm.prank(relayer);
        EIP7702Bundler.BatchExecutionResult memory batchResult = bundler.executeBatch(accounts, userOps, contexts);
        
        // Verify batch execution
        assertEq(batchResult.results.length, 2, "Should have 2 results");
        assertEq(batchResult.successCount, 2, "Both operations should succeed");
        assertTrue(batchResult.results[0].success, "First deposit should succeed");
        assertTrue(batchResult.results[1].success, "Second deposit should succeed");
        
        // Verify total deposits
        uint256 expectedTotal = DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2;
        assertEq(vault.userDeposits(user1), expectedTotal, "Total deposits should match");
        assertEq(usdc.balanceOf(address(vault)), expectedTotal, "Vault should hold total deposited amount");
    }
    
    function testPaymasterSponsorshipLimits() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Set very restrictive limits
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory restrictivePolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.001 ether, // Very low limit
            perTxGasLimit: 0.0005 ether,
            dailyTxLimit: 1,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, restrictivePolicy);
        
        // Create high-gas operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT),
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
        assertFalse(canSponsor, "Should not sponsor due to gas limits");
    }
    
    function testRemainingGasAllowance() public {
        // Check initial allowance
        (uint256 gasAllowance, uint256 txAllowance) = paymaster.getRemainingDailyAllowance(user1);
        
        EIP7702Paymaster.SponsorshipPolicy memory policy = paymaster.getEffectivePolicy(user1);
        assertEq(gasAllowance, policy.dailyGasLimit, "Should have full gas allowance initially");
        assertEq(txAllowance, policy.dailyTxLimit, "Should have full tx allowance initially");
        
        // After setting custom policy
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory customPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.5 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 10,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, customPolicy);
        
        (gasAllowance, txAllowance) = paymaster.getRemainingDailyAllowance(user1);
        assertEq(gasAllowance, 0.5 ether, "Should reflect custom gas limit");
        assertEq(txAllowance, 10, "Should reflect custom tx limit");
    }
}
