// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title RiskBasedSystemTest
 * @dev Comprehensive tests for the risk-based fund management system
 */
contract RiskBasedSystemTest is Test {
    
    // Core contracts
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    StrategyManager public strategyManager;
    MockERC20 public usdc;
    
    // Mock strategies
    MockStrategy public lowRiskStrategy;
    MockStrategy public mediumRiskStrategy;
    MockStrategy public highRiskStrategy;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    // Constants
    uint256 public constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 public constant MIN_DEPOSIT = 4e6; // $4 USDC
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy risk management contracts
        riskManager = new RiskProfileManager();
        strategyManager = new StrategyManager(address(riskManager));

        // Deploy vault first (without withdrawal manager)
        vault = new AbunfiVault(
            address(usdc),
            address(0), // No trusted forwarder for testing
            address(riskManager),
            address(0) // Withdrawal manager set later
        );

        // Deploy withdrawal manager with correct vault address
        withdrawalManager = new WithdrawalManager(address(vault), address(usdc));

        // Update vault with withdrawal manager address
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));
        
        // Deploy mock strategies
        lowRiskStrategy = new MockStrategy(address(usdc), "Low Risk Strategy", 400);
        mediumRiskStrategy = new MockStrategy(address(usdc), "Medium Risk Strategy", 600);
        highRiskStrategy = new MockStrategy(address(usdc), "High Risk Strategy", 1200);

        // Fund strategies with initial liquidity for withdrawals
        usdc.mint(address(lowRiskStrategy), 1000e6);
        usdc.mint(address(mediumRiskStrategy), 1000e6);
        usdc.mint(address(highRiskStrategy), 1000e6);
        
        // Setup strategies in strategy manager
        _setupStrategies();

        // Add strategies to vault as well
        vault.addStrategy(address(lowRiskStrategy), 3000); // 30% weight
        vault.addStrategy(address(mediumRiskStrategy), 4000); // 40% weight
        vault.addStrategy(address(highRiskStrategy), 3000); // 30% weight

        // Setup risk allocations
        _setupRiskAllocations();
        
        // Mint USDC to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);
        
        // Approve vault to spend USDC for all users
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // Helper functions for deposits (approvals already done in setup)
    function _approveAndDeposit(address user, uint256 amount) internal {
        vm.prank(user);
        vault.deposit(amount);
    }

    function _approveAndDepositWithRisk(address user, uint256 amount, RiskProfileManager.RiskLevel riskLevel) internal {
        vm.prank(user);
        vault.depositWithRiskLevel(amount, riskLevel);
    }

    function _setupStrategies() internal {
        // Add strategies to strategy manager
        strategyManager.addStrategy(
            address(lowRiskStrategy),
            3000, // 30% weight
            20,   // 20% risk score
            5000, // 50% max allocation
            1000  // 10% min allocation
        );
        
        strategyManager.addStrategy(
            address(mediumRiskStrategy),
            4000, // 40% weight
            50,   // 50% risk score
            6000, // 60% max allocation
            1500  // 15% min allocation
        );
        
        strategyManager.addStrategy(
            address(highRiskStrategy),
            3000, // 30% weight
            80,   // 80% risk score
            4000, // 40% max allocation
            500   // 5% min allocation
        );
    }
    
    function _setupRiskAllocations() internal {
        // LOW RISK: 70% low risk, 30% medium risk
        address[] memory lowRiskStrategies = new address[](2);
        uint256[] memory lowRiskAllocations = new uint256[](2);
        lowRiskStrategies[0] = address(lowRiskStrategy);
        lowRiskStrategies[1] = address(mediumRiskStrategy);
        lowRiskAllocations[0] = 7000; // 70%
        lowRiskAllocations[1] = 3000; // 30%
        
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            lowRiskStrategies,
            lowRiskAllocations
        );
        
        // MEDIUM RISK: 40% low, 40% medium, 20% high
        address[] memory mediumRiskStrategies = new address[](3);
        uint256[] memory mediumRiskAllocations = new uint256[](3);
        mediumRiskStrategies[0] = address(lowRiskStrategy);
        mediumRiskStrategies[1] = address(mediumRiskStrategy);
        mediumRiskStrategies[2] = address(highRiskStrategy);
        mediumRiskAllocations[0] = 4000; // 40%
        mediumRiskAllocations[1] = 4000; // 40%
        mediumRiskAllocations[2] = 2000; // 20%
        
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.MEDIUM,
            mediumRiskStrategies,
            mediumRiskAllocations
        );
        
        // HIGH RISK: 20% low, 30% medium, 50% high
        address[] memory highRiskStrategies = new address[](3);
        uint256[] memory highRiskAllocations = new uint256[](3);
        highRiskStrategies[0] = address(lowRiskStrategy);
        highRiskStrategies[1] = address(mediumRiskStrategy);
        highRiskStrategies[2] = address(highRiskStrategy);
        highRiskAllocations[0] = 2000; // 20%
        highRiskAllocations[1] = 3000; // 30%
        highRiskAllocations[2] = 5000; // 50%
        
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.HIGH,
            highRiskStrategies,
            highRiskAllocations
        );
    }
    
    // Risk Profile Management Tests
    
    function test_SetRiskProfile() public {
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);
        
        RiskProfileManager.RiskLevel level = riskManager.getUserRiskLevel(alice);
        assertEq(uint256(level), uint256(RiskProfileManager.RiskLevel.HIGH));
    }
    
    function test_DefaultRiskProfile() public {
        // Users should default to MEDIUM risk if not set
        RiskProfileManager.RiskLevel level = riskManager.getUserRiskLevel(alice);
        assertEq(uint256(level), uint256(RiskProfileManager.RiskLevel.MEDIUM));
    }
    
    function test_RiskProfileCooldown() public {
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);
        
        // Should not be able to update immediately
        vm.prank(alice);
        vm.expectRevert("Risk update cooldown not met");
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);
        
        // Should be able to update after cooldown
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);
        
        RiskProfileManager.RiskLevel level = riskManager.getUserRiskLevel(alice);
        assertEq(uint256(level), uint256(RiskProfileManager.RiskLevel.LOW));
    }
    
    // Deposit Tests
    
    function test_DepositWithDefaultRisk() public {
        uint256 depositAmount = 100e6; // $100

        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(vault.userDeposits(alice), depositAmount);
        assertGt(vault.userShares(alice), 0);
    }
    
    function test_DepositWithSpecificRisk() public {
        uint256 depositAmount = 100e6; // $100

        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.depositWithRiskLevel(depositAmount, RiskProfileManager.RiskLevel.HIGH);
        vm.stopPrank();

        assertEq(vault.userDeposits(alice), depositAmount);
        assertGt(vault.userShares(alice), 0);

        // Check that risk level was set
        RiskProfileManager.RiskLevel level = riskManager.getUserRiskLevel(alice);
        assertEq(uint256(level), uint256(RiskProfileManager.RiskLevel.HIGH));
    }
    
    function test_MinimumDeposit() public {
        vm.prank(alice);
        vm.expectRevert("Amount below minimum");
        vault.deposit(MIN_DEPOSIT - 1);

        // Should work with minimum deposit
        _approveAndDeposit(alice, MIN_DEPOSIT);
        assertEq(vault.userDeposits(alice), MIN_DEPOSIT);
    }
    
    // Withdrawal Tests
    
    function test_RequestWithdrawal() public {
        // First deposit
        uint256 depositAmount = 100e6;
        _approveAndDeposit(alice, depositAmount);

        uint256 shares = vault.userShares(alice);

        // Request withdrawal
        vm.prank(alice);
        uint256 requestId = vault.requestWithdrawal(shares / 2);

        assertEq(requestId, 0); // First request should have ID 0
    }
    
    function test_InstantWithdrawal() public {
        // First deposit
        uint256 depositAmount = 100e6;
        _approveAndDeposit(alice, depositAmount);
        
        uint256 shares = vault.userShares(alice);
        uint256 initialBalance = usdc.balanceOf(alice);
        
        // Instant withdrawal
        vm.prank(alice);
        vault.instantWithdrawal(shares / 2);
        
        // Should have received funds (minus fee)
        assertGt(usdc.balanceOf(alice), initialBalance);
    }
    
    // Interest Accrual Tests
    
    function test_InterestAccrual() public {
        uint256 depositAmount = 100e6;
        _approveAndDeposit(alice, depositAmount);

        // Manually allocate funds to strategies to simulate the allocation
        // In a real scenario, this would happen automatically
        uint256 allocation = depositAmount / 3; // Split equally among 3 strategies
        usdc.mint(address(vault), depositAmount); // Mint extra to vault for allocation

        // Simulate strategy allocation
        vm.startPrank(address(vault));
        usdc.transfer(address(lowRiskStrategy), allocation);
        usdc.transfer(address(mediumRiskStrategy), allocation);
        usdc.transfer(address(highRiskStrategy), allocation);
        vm.stopPrank();

        // Deposit to strategies
        lowRiskStrategy.deposit(allocation);
        mediumRiskStrategy.deposit(allocation);
        highRiskStrategy.deposit(allocation);

        // Simulate time passing and yield generation
        vm.warp(block.timestamp + 30 days);

        // Mock some yield in strategies
        lowRiskStrategy.addYield(5e6); // Add 5 USDC yield

        // Update interest
        vault.updateAccruedInterest(alice);

        uint256 accruedInterest = vault.getUserAccruedInterest(alice);
        assertGt(accruedInterest, 0);
    }
    
    // Risk Allocation Tests

    function test_RiskBasedAllocation() public {
        // Set different risk levels for users
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);

        vm.prank(bob);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);

        // Get allocations for each user
        (address[] memory aliceStrategies, uint256[] memory aliceAllocations) =
            strategyManager.calculateUserAllocation(alice, 1000e6);

        (address[] memory bobStrategies, uint256[] memory bobAllocations) =
            strategyManager.calculateUserAllocation(bob, 1000e6);

        // Alice (low risk) should have more allocation to low risk strategy
        // Bob (high risk) should have more allocation to high risk strategy
        assertEq(aliceStrategies.length, 2); // Low risk profile has 2 strategies
        assertEq(bobStrategies.length, 3);   // High risk profile has 3 strategies
    }

    // Edge Cases and Security Tests

    function test_ZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert("Amount below minimum");
        vault.deposit(0);
    }

    function test_ZeroWithdrawal() public {
        vm.prank(alice);
        vm.expectRevert("Cannot withdraw 0 shares");
        vault.withdraw(0);
    }

    function test_InsufficientShares() public {
        uint256 depositAmount = 100e6;
        _approveAndDeposit(alice, depositAmount);

        uint256 shares = vault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert("Insufficient shares");
        vault.withdraw(shares + 1);
    }

    function test_WithdrawalWindow() public {
        uint256 depositAmount = 100e6;
        _approveAndDeposit(alice, depositAmount);

        uint256 shares = vault.userShares(alice);

        // Request withdrawal
        vm.prank(alice);
        uint256 requestId = vault.requestWithdrawal(shares);

        // Should not be able to process immediately
        vm.prank(alice);
        vm.expectRevert("Withdrawal window not met");
        vault.processWithdrawal(requestId);

        // Should work after window period
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(alice);
        vault.processWithdrawal(requestId);
    }

    function test_MultipleUsersWithDifferentRiskProfiles() public {
        // Set different risk profiles
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);

        vm.prank(bob);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.MEDIUM);

        vm.prank(charlie);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);

        // All users deposit same amount
        uint256 depositAmount = 100e6;

        _approveAndDeposit(alice, depositAmount);
        _approveAndDeposit(bob, depositAmount);
        _approveAndDeposit(charlie, depositAmount);

        // All should have deposits recorded
        assertEq(vault.userDeposits(alice), depositAmount);
        assertEq(vault.userDeposits(bob), depositAmount);
        assertEq(vault.userDeposits(charlie), depositAmount);

        // All should have shares
        assertGt(vault.userShares(alice), 0);
        assertGt(vault.userShares(bob), 0);
        assertGt(vault.userShares(charlie), 0);
    }

    function test_RiskAllocationUpdate() public {
        // Test updating risk allocations
        address[] memory newStrategies = new address[](1);
        uint256[] memory newAllocations = new uint256[](1);
        newStrategies[0] = address(lowRiskStrategy);
        newAllocations[0] = 10000; // 100%

        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            newStrategies,
            newAllocations
        );

        (address[] memory strategies, uint256[] memory allocations) =
            strategyManager.getRiskLevelAllocation(RiskProfileManager.RiskLevel.LOW);

        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(lowRiskStrategy));
        assertEq(allocations[0], 10000);
    }

    function test_InvalidRiskAllocation() public {
        address[] memory strategies = new address[](2);
        uint256[] memory allocations = new uint256[](2);
        strategies[0] = address(lowRiskStrategy);
        strategies[1] = address(mediumRiskStrategy);
        allocations[0] = 6000; // 60%
        allocations[1] = 3000; // 30% - Total only 90%

        vm.expectRevert("Total allocation must equal 100%");
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            strategies,
            allocations
        );
    }

    function test_EmptyRiskAllocation() public {
        address[] memory strategies = new address[](0);
        uint256[] memory allocations = new uint256[](0);

        vm.expectRevert("Empty arrays");
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            strategies,
            allocations
        );
    }

    function test_ArrayLengthMismatch() public {
        address[] memory strategies = new address[](2);
        uint256[] memory allocations = new uint256[](1);
        strategies[0] = address(lowRiskStrategy);
        strategies[1] = address(mediumRiskStrategy);
        allocations[0] = 10000;

        vm.expectRevert("Arrays length mismatch");
        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            strategies,
            allocations
        );
    }

    // Integration Tests

    function test_FullUserJourney() public {
        // 1. User sets risk profile
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);

        // 2. User deposits funds
        uint256 depositAmount = 1000e6; // $1000
        _approveAndDepositWithRisk(alice, depositAmount, RiskProfileManager.RiskLevel.HIGH);

        // 3. Time passes, yield is generated
        vm.warp(block.timestamp + 30 days);
        highRiskStrategy.addYield(50e6); // Add 50 USDC yield

        // 4. User requests withdrawal
        uint256 shares = vault.userShares(alice);
        vm.prank(alice);
        uint256 requestId = vault.requestWithdrawal(shares / 2);

        // 5. Wait for withdrawal window
        vm.warp(block.timestamp + 7 days + 1);

        // 6. Process withdrawal
        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.processWithdrawal(requestId);

        // Should have received funds including yield
        assertGt(usdc.balanceOf(alice), balanceBefore);

        // Should still have remaining shares
        assertGt(vault.userShares(alice), 0);
    }
}
