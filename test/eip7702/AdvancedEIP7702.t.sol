// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/eip7702/SmartAccount.sol";
import "../../src/eip7702/Paymaster.sol";
import "../../src/eip7702/Bundler.sol";
import "../../src/mocks/MockERC20.sol";

contract AdvancedEIP7702Test is Test {
    SmartAccount public smartAccount;
    Paymaster public paymaster;
    Bundler public bundler;
    MockERC20 public mockUSDC;

    address public user = address(0x1);
    address public attacker = address(0x2);
    address public relayer = address(0x3);
    address public sponsor = address(0x4);

    uint256 public constant INITIAL_BALANCE = 1000e6;
    uint256 public constant GAS_LIMIT = 100000;

    event TransactionExecuted(address indexed user, bytes32 indexed txHash, bool success);
    event PaymasterUsed(address indexed user, uint256 gasUsed, uint256 gasCost);
    event BatchExecuted(address indexed bundler, uint256 transactionCount);

    function setUp() public {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy EIP-7702 contracts
        smartAccount = new SmartAccount();
        paymaster = new Paymaster(address(mockUSDC));
        bundler = new Bundler();

        // Setup initial balances
        mockUSDC.mint(user, INITIAL_BALANCE);
        mockUSDC.mint(sponsor, INITIAL_BALANCE);
        mockUSDC.mint(address(paymaster), INITIAL_BALANCE);

        // Setup approvals
        vm.prank(sponsor);
        mockUSDC.approve(address(paymaster), type(uint256).max);
    }

    // ============ Smart Account Tests ============

    function test_SmartAccount_BasicExecution() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(user);
        mockUSDC.approve(address(smartAccount), 100e6);

        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(user, keccak256(callData), true);

        vm.prank(user);
        bool success = smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            GAS_LIMIT
        );

        assertTrue(success, "Transaction should succeed");
    }

    function test_SmartAccount_BatchExecution() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = address(mockUSDC);
        targets[1] = address(mockUSDC);
        values[0] = 0;
        values[1] = 0;
        calldatas[0] = abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x5), 50e6);
        calldatas[1] = abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x6), 50e6);

        vm.prank(user);
        mockUSDC.approve(address(smartAccount), 100e6);

        vm.prank(user);
        bool[] memory results = smartAccount.executeBatch(targets, values, calldatas, GAS_LIMIT);

        assertTrue(results[0], "First transaction should succeed");
        assertTrue(results[1], "Second transaction should succeed");
    }

    function test_SmartAccount_UnauthorizedExecution() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            GAS_LIMIT
        );
    }

    function test_SmartAccount_GasLimitExceeded() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(user);
        vm.expectRevert("Gas limit exceeded");
        smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            1000 // Very low gas limit
        );
    }

    // ============ Paymaster Tests ============

    function test_Paymaster_SponsoredTransaction() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        uint256 gasCost = 50000; // Estimated gas cost

        vm.expectEmit(true, false, false, true);
        emit PaymasterUsed(user, gasCost, gasCost * tx.gasprice);

        vm.prank(relayer);
        bool success = paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            gasCost,
            sponsor
        );

        assertTrue(success, "Sponsored transaction should succeed");
    }

    function test_Paymaster_InsufficientSponsorBalance() public {
        // Drain sponsor balance
        vm.prank(sponsor);
        mockUSDC.transfer(address(0x7), INITIAL_BALANCE);

        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(relayer);
        vm.expectRevert("Insufficient sponsor balance");
        paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            50000,
            sponsor
        );
    }

    function test_Paymaster_InvalidSponsor() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(relayer);
        vm.expectRevert("Invalid sponsor");
        paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            50000,
            address(0) // Invalid sponsor
        );
    }

    // ============ Bundler Tests ============

    function test_Bundler_BatchTransactions() public {
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](2);
        
        ops[0] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x5), 50e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        ops[1] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x6), 50e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        vm.prank(user);
        mockUSDC.approve(address(bundler), 100e6);

        vm.expectEmit(true, false, false, true);
        emit BatchExecuted(address(bundler), 2);

        vm.prank(relayer);
        bool[] memory results = bundler.handleOps(ops);

        assertTrue(results[0], "First operation should succeed");
        assertTrue(results[1], "Second operation should succeed");
    }

    function test_Bundler_EmptyBatch() public {
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](0);

        vm.prank(relayer);
        vm.expectRevert("Empty batch");
        bundler.handleOps(ops);
    }

    function test_Bundler_PartialFailure() public {
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](2);
        
        ops[0] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x5), 50e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        // This will fail due to insufficient balance
        ops[1] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x6), INITIAL_BALANCE),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        vm.prank(user);
        mockUSDC.approve(address(bundler), type(uint256).max);

        vm.prank(relayer);
        bool[] memory results = bundler.handleOps(ops);

        assertTrue(results[0], "First operation should succeed");
        assertFalse(results[1], "Second operation should fail");
    }

    // ============ Security Tests ============

    function test_Security_ReentrancyProtection() public {
        // Test that contracts are protected against reentrancy attacks
        bytes memory maliciousCallData = abi.encodeWithSelector(
            this.maliciousReentrantCall.selector
        );

        vm.prank(user);
        vm.expectRevert("Reentrancy detected");
        smartAccount.executeTransaction(
            address(this),
            0,
            maliciousCallData,
            GAS_LIMIT
        );
    }

    function maliciousReentrantCall() external {
        // Attempt to call back into the smart account
        smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            abi.encodeWithSelector(mockUSDC.transfer.selector, attacker, 1000e6),
            GAS_LIMIT
        );
    }

    function test_Security_SignatureValidation() public {
        // Test that only properly signed transactions are executed
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        // Create invalid signature
        bytes memory invalidSig = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        vm.prank(attacker);
        vm.expectRevert("Invalid signature");
        smartAccount.executeTransactionWithSignature(
            address(mockUSDC),
            0,
            callData,
            GAS_LIMIT,
            invalidSig
        );
    }

    function test_Security_GasGriefing() public {
        // Test protection against gas griefing attacks
        bytes memory gasGriefingCallData = abi.encodeWithSelector(
            this.gasGriefingFunction.selector
        );

        vm.prank(user);
        vm.expectRevert("Gas limit exceeded");
        smartAccount.executeTransaction(
            address(this),
            0,
            gasGriefingCallData,
            GAS_LIMIT
        );
    }

    function gasGriefingFunction() external pure {
        // Consume excessive gas
        for (uint256 i = 0; i < 1000000; i++) {
            keccak256(abi.encode(i));
        }
    }

    // ============ Edge Cases ============

    function test_EdgeCase_ZeroValueTransfer() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            0
        );

        vm.prank(user);
        bool success = smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            GAS_LIMIT
        );

        assertTrue(success, "Zero value transfer should succeed");
    }

    function test_EdgeCase_SelfTransfer() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            user,
            100e6
        );

        vm.prank(user);
        mockUSDC.approve(address(smartAccount), 100e6);

        vm.prank(user);
        bool success = smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            GAS_LIMIT
        );

        assertTrue(success, "Self transfer should succeed");
    }

    function test_EdgeCase_MaxGasLimit() public {
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        vm.prank(user);
        mockUSDC.approve(address(smartAccount), 100e6);

        vm.prank(user);
        bool success = smartAccount.executeTransaction(
            address(mockUSDC),
            0,
            callData,
            type(uint256).max
        );

        assertTrue(success, "Max gas limit should work");
    }

    // ============ Integration Tests ============

    function test_Integration_FullGaslessFlow() public {
        // Complete gasless transaction flow using all components
        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        // 1. User approves smart account
        vm.prank(user);
        mockUSDC.approve(address(smartAccount), 100e6);

        // 2. Create user operation
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](1);
        ops[0] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: callData,
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        // 3. Bundler processes the operation
        vm.prank(relayer);
        bool[] memory results = bundler.handleOps(ops);

        assertTrue(results[0], "Gasless transaction should succeed");
        assertEq(mockUSDC.balanceOf(address(0x5)), 100e6, "Recipient should receive tokens");
    }

    function test_Integration_MultiUserBatch() public {
        address user2 = address(0x8);
        mockUSDC.mint(user2, INITIAL_BALANCE);

        // Setup approvals for both users
        vm.prank(user);
        mockUSDC.approve(address(bundler), 100e6);
        vm.prank(user2);
        mockUSDC.approve(address(bundler), 100e6);

        // Create operations for both users
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](2);
        ops[0] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x5), 50e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        ops[1] = Bundler.UserOperation({
            sender: user2,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x6), 75e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        vm.prank(relayer);
        bool[] memory results = bundler.handleOps(ops);

        assertTrue(results[0], "First user operation should succeed");
        assertTrue(results[1], "Second user operation should succeed");
        assertEq(mockUSDC.balanceOf(address(0x5)), 50e6, "First recipient should receive tokens");
        assertEq(mockUSDC.balanceOf(address(0x6)), 75e6, "Second recipient should receive tokens");
    }

    function test_Integration_PaymasterGasAccounting() public {
        uint256 initialPaymasterBalance = mockUSDC.balanceOf(address(paymaster));
        uint256 initialSponsorBalance = mockUSDC.balanceOf(sponsor);

        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        uint256 estimatedGasCost = 50000;

        vm.prank(relayer);
        paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            estimatedGasCost,
            sponsor
        );

        // Verify gas costs were deducted from sponsor
        assertLt(mockUSDC.balanceOf(sponsor), initialSponsorBalance, "Sponsor should pay gas costs");
        assertGt(mockUSDC.balanceOf(address(paymaster)), initialPaymasterBalance, "Paymaster should receive gas payment");
    }

    // ============ Failure Recovery Tests ============

    function test_FailureRecovery_PartialBatchFailure() public {
        Bundler.UserOperation[] memory ops = new Bundler.UserOperation[](3);

        // First operation - should succeed
        ops[0] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x5), 50e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        // Second operation - should fail (insufficient balance)
        ops[1] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x6), INITIAL_BALANCE * 2),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        // Third operation - should succeed
        ops[2] = Bundler.UserOperation({
            sender: user,
            target: address(mockUSDC),
            value: 0,
            callData: abi.encodeWithSelector(mockUSDC.transfer.selector, address(0x7), 25e6),
            gasLimit: GAS_LIMIT,
            sponsor: sponsor
        });

        vm.prank(user);
        mockUSDC.approve(address(bundler), type(uint256).max);

        vm.prank(relayer);
        bool[] memory results = bundler.handleOps(ops);

        assertTrue(results[0], "First operation should succeed");
        assertFalse(results[1], "Second operation should fail");
        assertTrue(results[2], "Third operation should succeed despite second failure");
    }

    function test_FailureRecovery_SponsorFailover() public {
        address backupSponsor = address(0x9);
        mockUSDC.mint(backupSponsor, INITIAL_BALANCE);

        vm.prank(backupSponsor);
        mockUSDC.approve(address(paymaster), type(uint256).max);

        // Drain primary sponsor
        vm.prank(sponsor);
        mockUSDC.transfer(address(0x10), INITIAL_BALANCE);

        bytes memory callData = abi.encodeWithSelector(
            mockUSDC.transfer.selector,
            address(0x5),
            100e6
        );

        // First attempt with drained sponsor should fail
        vm.prank(relayer);
        vm.expectRevert("Insufficient sponsor balance");
        paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            50000,
            sponsor
        );

        // Second attempt with backup sponsor should succeed
        vm.prank(relayer);
        bool success = paymaster.sponsorTransaction(
            user,
            address(mockUSDC),
            0,
            callData,
            50000,
            backupSponsor
        );

        assertTrue(success, "Transaction with backup sponsor should succeed");
    }
}
