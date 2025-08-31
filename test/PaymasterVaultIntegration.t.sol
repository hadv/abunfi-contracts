// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/eip7702/EIP7702Paymaster.sol";
import "../src/eip7702/EIP7702Bundler.sol";
import "../src/eip7702/AbunfiSmartAccount.sol";

/**
 * @title PaymasterVaultIntegrationTest
 * @dev Demonstrates meaningful integration between paymaster policies and vault operations
 * Shows how gas sponsorship affects user access to vault functionality
 */
contract PaymasterVaultIntegrationTest is Test {
    
    AbunfiVault public vault;
    MockERC20 public usdc;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;
    AbunfiSmartAccount public smartAccountImpl;
    
    address public owner = address(0x1001);
    address public premiumUser = address(0x1002);
    address public basicUser = address(0x1003);
    address public restrictedUser = address(0x1004);
    address public whitelistedUser = address(0x1005);
    
    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC
    uint256 public constant LARGE_DEPOSIT = 1000e6; // 1000 USDC
    
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event UserOperationSponsored(address indexed account, address indexed actualGasPrice, uint256 actualGasCost, uint256 actualGasUsed);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core infrastructure
        usdc = new MockERC20("USD Coin", "USDC", 6);
        smartAccountImpl = new AbunfiSmartAccount();
        paymaster = new EIP7702Paymaster();
        bundler = new EIP7702Bundler();
        vault = new AbunfiVault(address(usdc), address(bundler));
        
        // Configure paymaster and bundler
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);
        vm.deal(address(paymaster), 10 ether);
        
        // Setup users with USDC
        address[] memory users = new address[](4);
        users[0] = premiumUser;
        users[1] = basicUser;
        users[2] = restrictedUser;
        users[3] = whitelistedUser;
        
        for (uint i = 0; i < users.length; i++) {
            vm.deal(users[i], 1 ether);
            usdc.mint(users[i], 10000e6); // 10,000 USDC each
        }
        
        vm.stopPrank();
        
        // Users approve vault
        for (uint i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            usdc.approve(address(vault), type(uint256).max);
        }
    }
    
    function test_SetupDifferentUserTiers() public {
        vm.startPrank(owner);
        
        // Premium User: High limits, no restrictions
        EIP7702Paymaster.SponsorshipPolicy memory premiumPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(premiumUser, premiumPolicy);
        
        // Basic User: Moderate limits
        EIP7702Paymaster.SponsorshipPolicy memory basicPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.1 ether,
            perTxGasLimit: 0.01 ether,
            dailyTxLimit: 20,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(basicUser, basicPolicy);
        
        // Restricted User: Very low limits
        EIP7702Paymaster.SponsorshipPolicy memory restrictedPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.01 ether,
            perTxGasLimit: 0.001 ether,
            dailyTxLimit: 5,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(restrictedUser, restrictedPolicy);
        
        // Whitelisted User: Requires whitelist but high limits
        EIP7702Paymaster.SponsorshipPolicy memory whitelistPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 2 ether,
            perTxGasLimit: 0.2 ether,
            dailyTxLimit: 200,
            requiresWhitelist: true,
            isActive: true
        });
        paymaster.setAccountPolicy(whitelistedUser, whitelistPolicy);
        paymaster.setAccountWhitelist(whitelistedUser, true);
        
        vm.stopPrank();
        
        // Verify policies are set correctly
        (uint256 premiumGas, uint256 premiumTx) = paymaster.getRemainingDailyAllowance(premiumUser);
        (uint256 basicGas, uint256 basicTx) = paymaster.getRemainingDailyAllowance(basicUser);
        (uint256 restrictedGas, uint256 restrictedTx) = paymaster.getRemainingDailyAllowance(restrictedUser);
        (uint256 whitelistGas, uint256 whitelistTx) = paymaster.getRemainingDailyAllowance(whitelistedUser);
        
        assertEq(premiumGas, 1 ether, "Premium user should have 1 ETH gas allowance");
        assertEq(premiumTx, 100, "Premium user should have 100 tx allowance");
        
        assertEq(basicGas, 0.1 ether, "Basic user should have 0.1 ETH gas allowance");
        assertEq(basicTx, 20, "Basic user should have 20 tx allowance");
        
        assertEq(restrictedGas, 0.01 ether, "Restricted user should have 0.01 ETH gas allowance");
        assertEq(restrictedTx, 5, "Restricted user should have 5 tx allowance");
        
        assertEq(whitelistGas, 2 ether, "Whitelisted user should have 2 ETH gas allowance");
        assertEq(whitelistTx, 200, "Whitelisted user should have 200 tx allowance");
    }
    
    function test_RegularVaultOperations_AllUsersCanDeposit() public {
        // All users should be able to make regular deposits (paying their own gas)
        vm.prank(premiumUser);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.userDeposits(premiumUser), DEPOSIT_AMOUNT);
        
        vm.prank(basicUser);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.userDeposits(basicUser), DEPOSIT_AMOUNT);
        
        vm.prank(restrictedUser);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.userDeposits(restrictedUser), DEPOSIT_AMOUNT);
        
        vm.prank(whitelistedUser);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.userDeposits(whitelistedUser), DEPOSIT_AMOUNT);
    }
    
    function test_GasSponsorshipValidation_DifferentTransactionSizes() public {
        // Setup user policies first
        test_SetupDifferentUserTiers();
        
        // Create different sized vault operations
        AbunfiSmartAccount.UserOperation memory smallOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, DEPOSIT_AMOUNT),
            nonce: 0,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 200000, // Small gas limit
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        AbunfiSmartAccount.UserOperation memory largeOp = AbunfiSmartAccount.UserOperation({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(vault.deposit.selector, LARGE_DEPOSIT),
            nonce: 0,
            maxFeePerGas: 50 gwei, // Higher gas price
            maxPriorityFeePerGas: 5 gwei,
            gasLimit: 500000, // Large gas limit
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });
        
        // Test sponsorship validation for different users
        EIP7702Paymaster.UserOperationContext memory context;
        
        // Premium user: Should be able to sponsor both small and large operations
        context = EIP7702Paymaster.UserOperationContext({
            account: premiumUser,
            maxFeePerGas: smallOp.maxFeePerGas,
            gasLimit: smallOp.gasLimit,
            signature: ""
        });
        (bool canSponsorSmall, ) = paymaster.validateUserOperation(smallOp, context);
        assertTrue(canSponsorSmall, "Premium user should sponsor small operations");
        
        context.maxFeePerGas = largeOp.maxFeePerGas;
        context.gasLimit = largeOp.gasLimit;
        (bool canSponsorLarge, ) = paymaster.validateUserOperation(largeOp, context);
        assertTrue(canSponsorLarge, "Premium user should sponsor large operations");
        
        // Basic user: Should sponsor small but not large operations
        context = EIP7702Paymaster.UserOperationContext({
            account: basicUser,
            maxFeePerGas: smallOp.maxFeePerGas,
            gasLimit: smallOp.gasLimit,
            signature: ""
        });
        (canSponsorSmall, ) = paymaster.validateUserOperation(smallOp, context);
        assertTrue(canSponsorSmall, "Basic user should sponsor small operations");
        
        context.maxFeePerGas = largeOp.maxFeePerGas;
        context.gasLimit = largeOp.gasLimit;
        (canSponsorLarge, ) = paymaster.validateUserOperation(largeOp, context);
        assertFalse(canSponsorLarge, "Basic user should NOT sponsor large operations");
        
        // Restricted user: Should not sponsor either operation
        context = EIP7702Paymaster.UserOperationContext({
            account: restrictedUser,
            maxFeePerGas: smallOp.maxFeePerGas,
            gasLimit: smallOp.gasLimit,
            signature: ""
        });
        (canSponsorSmall, ) = paymaster.validateUserOperation(smallOp, context);
        assertFalse(canSponsorSmall, "Restricted user should NOT sponsor small operations");
        
        context.maxFeePerGas = largeOp.maxFeePerGas;
        context.gasLimit = largeOp.gasLimit;
        (canSponsorLarge, ) = paymaster.validateUserOperation(largeOp, context);
        assertFalse(canSponsorLarge, "Restricted user should NOT sponsor large operations");
    }
    
    function test_WhitelistRequirement_AffectsVaultAccess() public {
        // Setup user policies
        test_SetupDifferentUserTiers();
        
        // Create vault operation
        AbunfiSmartAccount.UserOperation memory vaultOp = AbunfiSmartAccount.UserOperation({
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
            account: whitelistedUser,
            maxFeePerGas: vaultOp.maxFeePerGas,
            gasLimit: vaultOp.gasLimit,
            signature: ""
        });
        
        // Whitelisted user should be able to get sponsorship
        (bool canSponsor, ) = paymaster.validateUserOperation(vaultOp, context);
        assertTrue(canSponsor, "Whitelisted user should get gas sponsorship");
        
        // Remove from whitelist
        vm.prank(owner);
        paymaster.setAccountWhitelist(whitelistedUser, false);
        
        // Should no longer be able to get sponsorship
        (canSponsor, ) = paymaster.validateUserOperation(vaultOp, context);
        assertFalse(canSponsor, "Non-whitelisted user should NOT get gas sponsorship");
        
        // But regular vault operations should still work
        vm.prank(whitelistedUser);
        vault.deposit(DEPOSIT_AMOUNT);
        assertEq(vault.userDeposits(whitelistedUser), DEPOSIT_AMOUNT, "Regular deposits should still work");
    }
    
    function test_PaymasterBalance_AffectsAllUsers() public {
        // Setup user policies
        test_SetupDifferentUserTiers();
        
        // Drain paymaster balance
        vm.prank(owner);
        paymaster.emergencyWithdraw();
        
        // Create vault operation
        AbunfiSmartAccount.UserOperation memory vaultOp = AbunfiSmartAccount.UserOperation({
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
        
        // Even premium users should not get sponsorship with empty paymaster
        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: premiumUser,
            maxFeePerGas: vaultOp.maxFeePerGas,
            gasLimit: vaultOp.gasLimit,
            signature: ""
        });
        
        (bool canSponsor, ) = paymaster.validateUserOperation(vaultOp, context);
        assertFalse(canSponsor, "Empty paymaster should not sponsor any operations");
        
        // Refund paymaster
        vm.deal(address(paymaster), 5 ether);
        
        // Should work again
        (canSponsor, ) = paymaster.validateUserOperation(vaultOp, context);
        assertTrue(canSponsor, "Funded paymaster should sponsor operations again");
    }
    
    function test_VaultIntegration_ShowsRealWorldUsage() public {
        // This test demonstrates how the paymaster would work in practice
        test_SetupDifferentUserTiers();
        
        // Scenario: Users want to make vault deposits
        // Premium users get gasless transactions for any size
        // Basic users get gasless for small transactions only
        // Restricted users must pay their own gas
        
        uint256 smallAmount = 50e6; // 50 USDC
        uint256 mediumAmount = 200e6; // 200 USDC
        uint256 largeAmount = 1000e6; // 1000 USDC
        
        // Test different transaction sizes - simplified without struct
        address[] memory testUsers = new address[](6);
        uint256[] memory testAmounts = new uint256[](6);
        uint256[] memory testGasLimits = new uint256[](6);
        uint256[] memory testGasPrices = new uint256[](6);
        bool[] memory shouldSponsor = new bool[](6);

        testUsers[0] = premiumUser; testAmounts[0] = smallAmount; testGasLimits[0] = 200000; testGasPrices[0] = 20 gwei; shouldSponsor[0] = true;
        testUsers[1] = premiumUser; testAmounts[1] = largeAmount; testGasLimits[1] = 400000; testGasPrices[1] = 50 gwei; shouldSponsor[1] = true;
        testUsers[2] = basicUser; testAmounts[2] = smallAmount; testGasLimits[2] = 200000; testGasPrices[2] = 20 gwei; shouldSponsor[2] = true;
        testUsers[3] = basicUser; testAmounts[3] = mediumAmount; testGasLimits[3] = 300000; testGasPrices[3] = 40 gwei; shouldSponsor[3] = false;
        testUsers[4] = restrictedUser; testAmounts[4] = smallAmount; testGasLimits[4] = 200000; testGasPrices[4] = 20 gwei; shouldSponsor[4] = false;
        testUsers[5] = whitelistedUser; testAmounts[5] = largeAmount; testGasLimits[5] = 500000; testGasPrices[5] = 60 gwei; shouldSponsor[5] = true;

        for (uint i = 0; i < testUsers.length; i++) {
            
            AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
                target: address(vault),
                value: 0,
                data: abi.encodeWithSelector(vault.deposit.selector, testAmounts[i]),
                nonce: 0,
                maxFeePerGas: testGasPrices[i],
                maxPriorityFeePerGas: testGasPrices[i] / 10,
                gasLimit: testGasLimits[i],
                paymaster: address(paymaster),
                paymasterData: "",
                signature: ""
            });

            EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
                account: testUsers[i],
                maxFeePerGas: testGasPrices[i],
                gasLimit: testGasLimits[i],
                signature: ""
            });

            (bool canSponsor, ) = paymaster.validateUserOperation(userOp, context);

            if (shouldSponsor[i]) {
                assertTrue(canSponsor, "Should sponsor this operation");
            } else {
                assertFalse(canSponsor, "Should NOT sponsor this operation");
            }
        }
    }
}
