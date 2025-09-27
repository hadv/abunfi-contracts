// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/eip7702/AbunfiSmartAccount.sol";
import "../../src/eip7702/EIP7702Paymaster.sol";
import "../../src/eip7702/EIP7702Bundler.sol";

/**
 * @title BasicEIP7702Test
 * @dev Basic tests for EIP-7702 contracts without delegation simulation
 */
contract BasicEIP7702Test is Test {
    AbunfiSmartAccount public smartAccount;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;

    address public owner = address(0x1001);
    address public user1 = address(0x1002);
    address public bundlerOperator = address(0x1004);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        smartAccount = new AbunfiSmartAccount();
        paymaster = new EIP7702Paymaster(address(0));
        bundler = new EIP7702Bundler();

        // Configure system
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);

        // Fund paymaster
        vm.deal(address(paymaster), 10 ether);

        vm.stopPrank();
    }

    function testSmartAccountDeployment() public {
        // Test that smart account deployed correctly
        assertTrue(address(smartAccount) != address(0));
    }

    function testPaymasterDeployment() public {
        // Test that paymaster deployed correctly
        assertTrue(address(paymaster) != address(0));
        assertEq(address(paymaster).balance, 10 ether);
    }

    function testBundlerDeployment() public {
        // Test that bundler deployed correctly
        assertTrue(address(bundler) != address(0));
        assertTrue(bundler.supportedPaymasters(address(paymaster)));
    }

    function testPaymasterConfiguration() public {
        // Test paymaster configuration
        EIP7702Paymaster.SponsorshipPolicy memory globalPolicy = paymaster.getEffectivePolicy(user1);

        assertTrue(globalPolicy.isActive);
        assertGt(globalPolicy.dailyGasLimit, 0);
        assertGt(globalPolicy.perTxGasLimit, 0);
        assertGt(globalPolicy.dailyTxLimit, 0);
    }

    function testPaymasterLimitConfiguration() public {
        vm.prank(owner);

        // Set custom policy for user
        EIP7702Paymaster.SponsorshipPolicy memory customPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.5 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 10,
            requiresWhitelist: true,
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setAccountPolicy(user1, customPolicy);

        // Verify policy was set
        EIP7702Paymaster.SponsorshipPolicy memory retrievedPolicy = paymaster.getEffectivePolicy(user1);
        assertEq(retrievedPolicy.dailyGasLimit, 0.5 ether);
        assertEq(retrievedPolicy.perTxGasLimit, 0.1 ether);
        assertEq(retrievedPolicy.dailyTxLimit, 10);
        assertTrue(retrievedPolicy.requiresWhitelist);
        assertTrue(retrievedPolicy.isActive);
    }

    function testPaymasterWhitelisting() public {
        vm.startPrank(owner);

        // Set policy requiring whitelist
        EIP7702Paymaster.SponsorshipPolicy memory whitelistPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: true,
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setAccountPolicy(user1, whitelistPolicy);

        // User should not be whitelisted initially
        EIP7702Paymaster.AccountState memory state = paymaster.getAccountState(user1);
        assertFalse(state.isWhitelisted);

        // Whitelist the user
        paymaster.setAccountWhitelist(user1, true);

        // Verify user is now whitelisted
        state = paymaster.getAccountState(user1);
        assertTrue(state.isWhitelisted);

        vm.stopPrank();
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

    function testBundlerConfiguration() public {
        // Test bundler configuration
        assertTrue(bundler.supportedPaymasters(address(paymaster)));

        // Test adding another paymaster
        EIP7702Paymaster newPaymaster = new EIP7702Paymaster(address(0));

        vm.prank(owner);
        bundler.addPaymaster(address(newPaymaster));

        assertTrue(bundler.supportedPaymasters(address(newPaymaster)));

        // Test removing paymaster
        vm.prank(owner);
        bundler.removePaymaster(address(newPaymaster));

        assertFalse(bundler.supportedPaymasters(address(newPaymaster)));
    }

    function testPaymasterRemainingAllowance() public {
        // Test getting remaining allowance for a user
        (uint256 gasAllowance, uint256 txAllowance) = paymaster.getRemainingDailyAllowance(user1);

        // Should have full allowance initially
        EIP7702Paymaster.SponsorshipPolicy memory policy = paymaster.getEffectivePolicy(user1);
        assertEq(gasAllowance, policy.dailyGasLimit);
        assertEq(txAllowance, policy.dailyTxLimit);
    }

    function testPaymasterEmergencyControls() public {
        // Test pause functionality
        vm.prank(owner);
        paymaster.setPaused(true);

        // Create a mock user operation for validation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: address(0),
            value: 0,
            data: "",
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 300000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: user1, maxFeePerGas: userOp.maxFeePerGas, gasLimit: userOp.gasLimit, signature: ""
        });

        // Should fail validation when paused
        (bool canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor);

        // Unpause
        vm.prank(owner);
        paymaster.setPaused(false);

        // Should work when unpaused
        (canSponsor,) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor);
    }
}
