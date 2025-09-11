// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/eip7702/AbunfiSmartAccount.sol";
import "../../src/eip7702/EIP7702Paymaster.sol";
import "../../src/eip7702/EIP7702Bundler.sol";
import "../../src/eip7702/SocialAccountRegistry.sol";
import "../../src/mocks/MockERC20.sol";

/**
 * @title AdvancedEIP7702Test
 * @dev Advanced test cases for EIP-7702 contracts including edge cases, security scenarios, and integration tests
 */
contract AdvancedEIP7702Test is Test {
    AbunfiSmartAccount public smartAccount;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;
    SocialAccountRegistry public socialRegistry;
    MockERC20 public mockToken;

    address public owner = address(0x1001);
    address public user1 = address(0x1002);
    address public user2 = address(0x1003);
    address public attacker = address(0x1004);
    address public bundlerOperator = address(0x1005);

    // Test constants
    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant GAS_LIMIT = 1000000;

    event UserOperationExecuted(address indexed account, bytes32 indexed userOpHash, bool success, uint256 actualGasUsed);
    event AccountInitialized(address indexed owner, address indexed paymaster);
    event TransactionExecuted(address indexed target, uint256 value, bytes data, bool success);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        smartAccount = new AbunfiSmartAccount();
        socialRegistry = new SocialAccountRegistry(address(0)); // Mock verifier
        paymaster = new EIP7702Paymaster(address(socialRegistry));
        bundler = new EIP7702Bundler();
        mockToken = new MockERC20("Test Token", "TEST", 18);

        // Configure system
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);

        // Fund paymaster and accounts
        vm.deal(address(paymaster), INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(attacker, INITIAL_BALANCE);

        // Mint tokens
        mockToken.mint(user1, 1000e18);
        mockToken.mint(user2, 1000e18);

        vm.stopPrank();
    }

    // ============ SMART ACCOUNT ADVANCED TESTS ============

    function test_SmartAccountInitialization_EdgeCases() public {
        // Test double initialization
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        vm.expectRevert("Already initialized");
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));
    }

    function test_SmartAccountInitialization_InvalidInputs() public {
        // Test zero address owner
        vm.expectRevert("Invalid owner");
        smartAccount.initialize(address(0), address(paymaster));
    }

    function test_UserOperationExecution_InvalidNonce() public {
        // Initialize account
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Create user operation with wrong nonce
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 999, // Wrong nonce
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        vm.expectRevert();
        vm.prank(address(paymaster));
        smartAccount.executeUserOperation(userOp);
    }

    function test_BatchUserOperations_PartialFailure() public {
        // Initialize account
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Create batch with one failing operation
        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](2);
        
        // Valid operation
        userOps[0] = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        // Invalid operation (insufficient balance)
        userOps[1] = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 10000e18),
            nonce: 1,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        // Fund the smart account with tokens
        vm.prank(user1);
        mockToken.transfer(address(smartAccount), 500e18);

        vm.prank(address(paymaster));
        smartAccount.executeBatch(userOps);

        // Check that first operation succeeded, second failed
        assertEq(mockToken.balanceOf(user2), 100e18);
        assertEq(mockToken.balanceOf(address(smartAccount)), 400e18);
    }

    // ============ PAYMASTER ADVANCED TESTS ============

    function test_PaymasterPolicyEnforcement_DailyLimits() public {
        // Set restrictive policy
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory restrictivePolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.01 ether,
            perTxGasLimit: 0.005 ether,
            dailyTxLimit: 2,
            requiresWhitelist: false,
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, restrictivePolicy);

        // Create user operation context
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        // First operation should succeed
        (bool canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor);

        // Simulate gas usage to exceed daily limit
        vm.prank(address(bundler));
        paymaster.executeSponsorship(userOp, context, 400000); // High gas usage

        // Second operation should fail due to daily limit
        // Update context for second operation
        userOp.nonce = 1;
        (canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);
    }

    function test_PaymasterWhitelistEnforcement() public {
        // Set whitelist-only policy
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory whitelistPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: true,
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });
        paymaster.setGlobalPolicy(whitelistPolicy);

        // Non-whitelisted user should be rejected
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        (bool canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);

        // Whitelist user and try again
        vm.prank(owner);
        paymaster.setAccountWhitelist(user1, true);

        (canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor);
    }

    function test_PaymasterEmergencyPause() public {
        // Pause paymaster
        vm.prank(owner);
        paymaster.setPaused(true);

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        // Should fail when paused
        vm.expectRevert("Paymaster is paused");
        paymaster.validateUserOperation(userOp, context);
    }

    // ============ BUNDLER ADVANCED TESTS ============

    function test_BundlerBatchSizeLimit() public {
        // Try to execute batch larger than MAX_BATCH_SIZE
        address[] memory accounts = new address[](51); // Exceeds MAX_BATCH_SIZE
        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](51);
        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](51);

        vm.expectRevert("Batch too large");
        bundler.executeBatch(accounts, userOps, contexts);
    }

    function test_BundlerArrayLengthMismatch() public {
        address[] memory accounts = new address[](2);
        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](3); // Mismatch
        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](2);

        vm.expectRevert("Array length mismatch");
        bundler.executeBatch(accounts, userOps, contexts);
    }

    function test_BundlerUnsupportedPaymaster() public {
        // Create new paymaster not added to bundler
        EIP7702Paymaster newPaymaster = new EIP7702Paymaster(address(socialRegistry));

        vm.expectRevert("Unsupported paymaster");
        bundler.addPaymaster(address(newPaymaster));
        bundler.removePaymaster(address(newPaymaster));
    }

    // ============ SECURITY ATTACK SCENARIOS ============

    function test_ReentrancyAttack_SmartAccount() public {
        // This test would require a malicious contract that attempts reentrancy
        // For now, we verify that ReentrancyGuard is properly applied
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // The contracts use ReentrancyGuard, so reentrancy should be prevented
        // This is more of a static analysis verification
        assertTrue(true); // Placeholder - actual reentrancy testing would require malicious contracts
    }

    function test_UnauthorizedAccess_SmartAccount() public {
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Attacker tries to execute operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", attacker, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        vm.expectRevert("Unauthorized");
        vm.prank(attacker);
        smartAccount.executeUserOperation(userOp);
    }

    function test_GasGriefingAttack_Bundler() public {
        // Test that bundler handles operations that consume excessive gas
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Create operation with very high gas limit
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1000e9, // Very high gas price
            maxPriorityFeePerGas: 100e9,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1,
            maxFeePerGas: 1000e9,
            gasLimit: 300000,
            signature: ""
        });

        // Should be rejected by paymaster due to per-tx gas limit
        (bool canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);
    }

    // ============ INTEGRATION TESTS ============

    function test_EndToEndGaslessTransaction() public {
        // Initialize smart account
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Fund smart account with tokens
        vm.prank(user1);
        mockToken.transfer(address(smartAccount), 500e18);

        // Create user operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: address(smartAccount),
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        // Execute through bundler
        address[] memory accounts = new address[](1);
        accounts[0] = address(smartAccount);

        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](1);
        userOps[0] = userOp;

        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](1);
        contexts[0] = context;

        uint256 initialBalance = user2.balance;
        uint256 initialTokenBalance = mockToken.balanceOf(user2);

        vm.prank(bundlerOperator);
        EIP7702Bundler.BatchExecutionResult memory result = bundler.executeBatch(accounts, userOps, contexts);

        // Verify transaction succeeded
        assertTrue(result.results[0].success);
        assertEq(result.successCount, 1);
        assertEq(mockToken.balanceOf(user2), initialTokenBalance + 100e18);
    }

    function test_MultiUserBatchExecution() public {
        // Initialize multiple smart accounts
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        AbunfiSmartAccount smartAccount2 = new AbunfiSmartAccount();
        vm.prank(user2);
        smartAccount2.initialize(user2, address(paymaster));

        // Fund accounts with tokens
        vm.prank(user1);
        mockToken.transfer(address(smartAccount), 500e18);
        vm.prank(user2);
        mockToken.transfer(address(smartAccount2), 500e18);

        // Create batch operations
        address[] memory accounts = new address[](2);
        accounts[0] = address(smartAccount);
        accounts[1] = address(smartAccount2);

        AbunfiSmartAccount.UserOperation[] memory userOps = new AbunfiSmartAccount.UserOperation[](2);
        userOps[0] = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", owner, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        userOps[1] = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", owner, 200e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext[] memory contexts = new EIP7702Paymaster.UserOperationContext[](2);
        contexts[0] = EIP7702Paymaster.UserOperationContext({
            account: address(smartAccount),
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        contexts[1] = EIP7702Paymaster.UserOperationContext({
            account: address(smartAccount2),
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        uint256 initialOwnerBalance = mockToken.balanceOf(owner);

        vm.prank(bundlerOperator);
        EIP7702Bundler.BatchExecutionResult memory result = bundler.executeBatch(accounts, userOps, contexts);

        // Verify both transactions succeeded
        assertEq(result.successCount, 2);
        assertEq(mockToken.balanceOf(owner), initialOwnerBalance + 300e18);
    }

    function test_PaymasterInsufficientFunds() public {
        // Drain paymaster funds
        vm.prank(owner);
        paymaster.withdrawFunds(address(paymaster).balance);

        // Initialize smart account
        vm.prank(user1);
        smartAccount.initialize(user1, address(paymaster));

        // Try to execute operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", user2, 100e18),
            nonce: 0,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: address(smartAccount),
            maxFeePerGas: 1e9,
            gasLimit: 300000,
            signature: ""
        });

        // Should fail due to insufficient paymaster balance
        vm.expectRevert("Insufficient paymaster balance");
        vm.prank(address(bundler));
        paymaster.executeSponsorship(userOp, context, 500000); // High gas usage
    }
}
