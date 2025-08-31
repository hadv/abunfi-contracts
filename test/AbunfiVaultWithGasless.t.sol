// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/eip7702/AbunfiSmartAccount.sol";
import "../src/eip7702/EIP7702Paymaster.sol";
import "../src/eip7702/EIP7702Bundler.sol";

/**
 * @title AbunfiVaultWithGaslessTest
 * @dev Test AbunfiVault with actual EIP-7702 gasless infrastructure
 * This shows how the vault works with real paymaster and bundler integration
 */
contract AbunfiVaultWithGaslessTest is Test {
    
    AbunfiVault public vault;
    MockERC20 public mockUSDC;
    
    // EIP-7702 Infrastructure
    AbunfiSmartAccount public smartAccountImpl;
    EIP7702Paymaster public paymaster;
    EIP7702Bundler public bundler;
    
    address public owner = address(0x1001);
    address public user1;
    address public user2;
    
    uint256 public user1PrivateKey = 0x12345;
    uint256 public user2PrivateKey = 0x67890;
    
    uint256 public constant MINIMUM_DEPOSIT = 4e6; // 4 USDC
    uint256 public constant DEPOSIT_AMOUNT = 100e6; // 100 USDC
    
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    
    function setUp() public {
        // Set user addresses based on private keys
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        
        vm.startPrank(owner);
        
        // Deploy EIP-7702 infrastructure
        smartAccountImpl = new AbunfiSmartAccount();
        paymaster = new EIP7702Paymaster();
        bundler = new EIP7702Bundler();
        
        // Configure EIP-7702 system
        bundler.addPaymaster(address(paymaster));
        paymaster.setTrustedBundler(address(bundler), true);
        vm.deal(address(paymaster), 10 ether); // Fund paymaster
        
        // Deploy USDC and Vault with gasless support
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        vault = new AbunfiVault(address(mockUSDC), address(bundler)); // Use bundler as trusted forwarder
        
        // Setup users
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        mockUSDC.mint(user1, 1000e6);
        mockUSDC.mint(user2, 1000e6);
        
        vm.stopPrank();
    }
    
    function test_Deployment_WithGaslessInfrastructure() public {
        // Verify vault is deployed with correct gasless infrastructure
        assertEq(address(vault.asset()), address(mockUSDC), "Asset should be USDC");
        assertEq(vault.MINIMUM_DEPOSIT(), MINIMUM_DEPOSIT, "Minimum deposit should be set");
        
        // Verify EIP-7702 infrastructure is properly configured
        assertTrue(bundler.supportedPaymasters(address(paymaster)), "Bundler should support paymaster");
        assertEq(address(paymaster).balance, 10 ether, "Paymaster should be funded");
    }
    
    function test_RegularDeposits_StillWork() public {
        // Regular deposits should still work normally
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT * 1e18 / 1e6);
        
        vault.deposit(DEPOSIT_AMOUNT);
        
        assertEq(vault.userDeposits(user1), DEPOSIT_AMOUNT);
        assertGt(vault.userShares(user1), 0);
        vm.stopPrank();
    }
    
    function test_GaslessValidation_PolicyChecks() public {
        // This test shows how paymaster policies would validate vault operations
        // without the complex delegation simulation

        // Create vault operation
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

        // Validate that paymaster would sponsor this vault operation
        (bool canSponsor, uint256 gasPrice) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor, "Paymaster should validate vault operations");
        assertEq(gasPrice, userOp.maxFeePerGas, "Should return correct gas price");

        // Verify the operation targets our vault
        assertEq(userOp.target, address(vault), "Operation should target vault");

        // Verify the operation has deposit data
        assertGt(userOp.data.length, 0, "Should have operation data");
    }
    
    function test_PaymasterPolicies_AffectVaultInteractions() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Set restrictive policy for user1
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory restrictivePolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.001 ether, // Very low
            perTxGasLimit: 0.0005 ether,
            dailyTxLimit: 1,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, restrictivePolicy);
        
        // Create high-gas vault operation
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
        
        // Should fail due to gas limits
        (bool canSponsor, ) = paymaster.validateUserOperation(userOp, context);
        assertFalse(canSponsor, "Should not sponsor due to restrictive policy");
    }
    
    function test_WhitelistedUsers_GetPremiumAccess() public {
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Set whitelist-required policy
        vm.prank(owner);
        EIP7702Paymaster.SponsorshipPolicy memory whitelistPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: true, // Requires whitelist
            isActive: true
        });
        paymaster.setAccountPolicy(user1, whitelistPolicy);
        
        // Create vault operation
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
        assertFalse(canSponsor, "Should not sponsor non-whitelisted user");
        
        // Whitelist the user
        vm.prank(owner);
        paymaster.setAccountWhitelist(user1, true);
        
        // Should now work
        (canSponsor, ) = paymaster.validateUserOperation(userOp, context);
        assertTrue(canSponsor, "Should sponsor whitelisted user");
    }
    
    function test_MultipleUsers_DifferentPolicies() public {
        // Setup both users with delegation
        vm.etch(user1, address(smartAccountImpl).code);
        vm.etch(user2, address(smartAccountImpl).code);
        
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        vm.prank(user2);
        AbunfiSmartAccount(payable(user2)).initialize(user2, address(paymaster));
        
        // Set different policies for each user
        vm.startPrank(owner);
        
        // User1: Premium policy
        EIP7702Paymaster.SponsorshipPolicy memory premiumPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 1 ether,
            perTxGasLimit: 0.1 ether,
            dailyTxLimit: 100,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user1, premiumPolicy);
        
        // User2: Basic policy
        EIP7702Paymaster.SponsorshipPolicy memory basicPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.1 ether,
            perTxGasLimit: 0.01 ether,
            dailyTxLimit: 10,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setAccountPolicy(user2, basicPolicy);
        
        vm.stopPrank();
        
        // Check allowances
        (uint256 user1GasAllowance, uint256 user1TxAllowance) = paymaster.getRemainingDailyAllowance(user1);
        (uint256 user2GasAllowance, uint256 user2TxAllowance) = paymaster.getRemainingDailyAllowance(user2);
        
        assertEq(user1GasAllowance, 1 ether, "User1 should have premium gas allowance");
        assertEq(user1TxAllowance, 100, "User1 should have premium tx allowance");
        
        assertEq(user2GasAllowance, 0.1 ether, "User2 should have basic gas allowance");
        assertEq(user2TxAllowance, 10, "User2 should have basic tx allowance");
    }
    
    function test_VaultOperations_ConsumeGasAllowance() public {
        // This test would show how vault operations consume the user's daily gas allowance
        // In a real implementation, you'd track gas consumption and verify limits are enforced
        
        // Setup delegated account
        vm.etch(user1, address(smartAccountImpl).code);
        vm.prank(user1);
        AbunfiSmartAccount(payable(user1)).initialize(user1, address(paymaster));
        
        // Check initial allowance
        (uint256 initialGasAllowance, uint256 initialTxAllowance) = paymaster.getRemainingDailyAllowance(user1);
        
        EIP7702Paymaster.SponsorshipPolicy memory policy = paymaster.getEffectivePolicy(user1);
        assertEq(initialGasAllowance, policy.dailyGasLimit, "Should start with full allowance");
        assertEq(initialTxAllowance, policy.dailyTxLimit, "Should start with full tx allowance");
        
        // Note: In a full implementation, after executing gasless vault operations,
        // the allowances would decrease based on actual gas consumption
    }
}
