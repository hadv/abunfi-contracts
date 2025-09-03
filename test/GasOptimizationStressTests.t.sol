// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";

/**
 * @title GasOptimizationStressTests
 * @dev Tests for gas optimization and performance under stress conditions
 * Critical for production DeFi applications to maintain efficiency at scale
 */
contract GasOptimizationStressTestsTest is Test {
    AbunfiVault public vault;
    MockERC20 public mockUSDC;
    MockStrategy public mockStrategy;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;

    address public owner;
    address[] public users;
    uint256 constant NUM_USERS = 100;
    uint256 constant DEPOSIT_AMOUNT = 1000 * 10**6; // 1k USDC

    // Gas limit thresholds for production readiness
    uint256 constant MAX_DEPOSIT_GAS = 200_000;
    uint256 constant MAX_WITHDRAW_GAS = 250_000;
    uint256 constant MAX_HARVEST_GAS = 300_000;
    uint256 constant MAX_REBALANCE_GAS = 500_000;

    event GasUsageRecorded(string operation, uint256 gasUsed, bool withinLimit);

    function setUp() public {
        owner = address(this);

        // Deploy contracts
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        riskManager = new RiskProfileManager();

        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(0) // Temporary
        );

        withdrawalManager = new WithdrawalManager(address(vault), address(mockUSDC));
        vault.updateRiskManagers(address(riskManager), address(withdrawalManager));

        mockStrategy = new MockStrategy(address(mockUSDC), "Mock Strategy", 500); // 5% APY
        vault.addStrategy(address(mockStrategy));

        // Create users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
            mockUSDC.mint(users[i], DEPOSIT_AMOUNT * 10);
        }
    }

    // ============ DEPOSIT GAS OPTIMIZATION TESTS ============

    function test_GasOptimization_SingleDeposit() public {
        address user = users[0];
        
        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Single Deposit", gasUsed, gasUsed <= MAX_DEPOSIT_GAS);
        assertTrue(gasUsed <= MAX_DEPOSIT_GAS, "Single deposit should be gas efficient");
    }

    function test_GasOptimization_MultipleDeposits() public {
        // Test gas usage doesn't increase significantly with multiple deposits
        address user = users[0];
        
        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT * 5);
        
        // First deposit
        uint256 gasStart = gasleft();
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 firstDepositGas = gasStart - gasleft();
        
        // Second deposit (should be similar gas usage)
        gasStart = gasleft();
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 secondDepositGas = gasStart - gasleft();
        
        vm.stopPrank();

        emit GasUsageRecorded("First Deposit", firstDepositGas, firstDepositGas <= MAX_DEPOSIT_GAS);
        emit GasUsageRecorded("Second Deposit", secondDepositGas, secondDepositGas <= MAX_DEPOSIT_GAS);

        // Second deposit should not use significantly more gas
        uint256 gasIncrease = secondDepositGas > firstDepositGas ? 
            secondDepositGas - firstDepositGas : 0;
        assertTrue(gasIncrease <= 50_000, "Gas usage should not increase significantly");
    }

    function test_GasOptimization_DepositWithManyUsers() public {
        // Setup many users with deposits first
        for (uint256 i = 0; i < 50; i++) {
            vm.startPrank(users[i]);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }

        // Test gas usage for new deposit with many existing users
        address newUser = users[51];
        vm.startPrank(newUser);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Deposit with Many Users", gasUsed, gasUsed <= MAX_DEPOSIT_GAS);
        assertTrue(gasUsed <= MAX_DEPOSIT_GAS, "Deposit gas should not scale with user count");
    }

    // ============ WITHDRAWAL GAS OPTIMIZATION TESTS ============

    function test_GasOptimization_SingleWithdrawal() public {
        address user = users[0];
        
        // Setup deposit first
        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        
        uint256 userShares = vault.userShares(user);
        
        uint256 gasStart = gasleft();
        vault.withdraw(userShares);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Single Withdrawal", gasUsed, gasUsed <= MAX_WITHDRAW_GAS);
        assertTrue(gasUsed <= MAX_WITHDRAW_GAS, "Single withdrawal should be gas efficient");
    }

    function test_GasOptimization_WithdrawalRequestProcessing() public {
        address user = users[0];
        
        // Setup deposit
        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        
        uint256 userShares = vault.userShares(user);
        
        // Request withdrawal
        uint256 gasStart = gasleft();
        uint256 requestId = vault.requestWithdrawal(userShares);
        uint256 requestGas = gasStart - gasleft();
        
        // Fast forward past withdrawal window
        vm.warp(block.timestamp + 8 days);
        
        // Process withdrawal
        gasStart = gasleft();
        vault.processWithdrawal(requestId);
        uint256 processGas = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Withdrawal Request", requestGas, requestGas <= MAX_WITHDRAW_GAS);
        emit GasUsageRecorded("Withdrawal Processing", processGas, processGas <= MAX_WITHDRAW_GAS);

        assertTrue(requestGas <= MAX_WITHDRAW_GAS, "Withdrawal request should be gas efficient");
        assertTrue(processGas <= MAX_WITHDRAW_GAS, "Withdrawal processing should be gas efficient");
    }

    // ============ STRATEGY OPERATION GAS TESTS ============

    function test_GasOptimization_StrategyHarvest() public {
        // Setup deposits to generate yield
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }

        // Add yield to strategy
        mockStrategy.addYield(1000 * 10**6); // 1000 USDC yield

        // Test harvest gas usage
        uint256 gasStart = gasleft();
        vm.prank(address(vault));
        mockStrategy.harvest();
        uint256 gasUsed = gasStart - gasleft();

        emit GasUsageRecorded("Strategy Harvest", gasUsed, gasUsed <= MAX_HARVEST_GAS);
        assertTrue(gasUsed <= MAX_HARVEST_GAS, "Strategy harvest should be gas efficient");
    }

    function test_GasOptimization_MultipleStrategyOperations() public {
        // Deploy additional strategies
        MockStrategy strategy2 = new MockStrategy(address(mockUSDC), "Strategy 2", 400); // 4% APY
        MockStrategy strategy3 = new MockStrategy(address(mockUSDC), "Strategy 3", 600); // 6% APY
        
        vault.addStrategy(address(strategy2));
        vault.addStrategy(address(strategy3));

        // Setup deposits
        vm.startPrank(users[0]);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Test gas usage with multiple strategies
        uint256 gasStart = gasleft();
        vm.prank(address(vault));
        mockStrategy.harvest();
        uint256 gasUsed = gasStart - gasleft();

        emit GasUsageRecorded("Multi-Strategy Harvest", gasUsed, gasUsed <= MAX_HARVEST_GAS);
        assertTrue(gasUsed <= MAX_HARVEST_GAS, "Multi-strategy operations should be gas efficient");
    }

    // ============ BATCH OPERATION TESTS ============

    function test_GasOptimization_BatchDeposits() public {
        // Simulate batch deposits from multiple users in same block
        uint256 totalGas = 0;
        uint256 numBatchUsers = 10;

        for (uint256 i = 0; i < numBatchUsers; i++) {
            vm.startPrank(users[i]);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            
            uint256 gasStart = gasleft();
            vault.deposit(DEPOSIT_AMOUNT);
            uint256 gasUsed = gasStart - gasleft();
            totalGas += gasUsed;
            
            vm.stopPrank();
        }

        uint256 avgGasPerDeposit = totalGas / numBatchUsers;
        emit GasUsageRecorded("Average Batch Deposit", avgGasPerDeposit, avgGasPerDeposit <= MAX_DEPOSIT_GAS);
        
        assertTrue(avgGasPerDeposit <= MAX_DEPOSIT_GAS, "Batch deposits should maintain efficiency");
    }

    function test_GasOptimization_BatchWithdrawals() public {
        uint256 numBatchUsers = 10;
        
        // Setup deposits first
        for (uint256 i = 0; i < numBatchUsers; i++) {
            vm.startPrank(users[i]);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }

        // Batch withdrawals
        uint256 totalGas = 0;
        for (uint256 i = 0; i < numBatchUsers; i++) {
            vm.startPrank(users[i]);
            uint256 userShares = vault.userShares(users[i]);
            
            uint256 gasStart = gasleft();
            vault.withdraw(userShares);
            uint256 gasUsed = gasStart - gasleft();
            totalGas += gasUsed;
            
            vm.stopPrank();
        }

        uint256 avgGasPerWithdrawal = totalGas / numBatchUsers;
        emit GasUsageRecorded("Average Batch Withdrawal", avgGasPerWithdrawal, avgGasPerWithdrawal <= MAX_WITHDRAW_GAS);
        
        assertTrue(avgGasPerWithdrawal <= MAX_WITHDRAW_GAS, "Batch withdrawals should maintain efficiency");
    }

    // ============ STRESS TEST SCENARIOS ============

    function test_StressTest_HighVolumeOperations() public {
        uint256 numOperations = 50;
        uint256 maxGasPerOperation = 0;
        uint256 totalGas = 0;

        // High volume deposit/withdraw cycles
        for (uint256 i = 0; i < numOperations; i++) {
            address user = users[i % NUM_USERS];
            
            vm.startPrank(user);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            
            // Deposit
            uint256 gasStart = gasleft();
            vault.deposit(DEPOSIT_AMOUNT);
            uint256 depositGas = gasStart - gasleft();
            
            // Immediate withdrawal
            uint256 userShares = vault.userShares(user);
            gasStart = gasleft();
            vault.withdraw(userShares);
            uint256 withdrawGas = gasStart - gasleft();
            
            vm.stopPrank();

            uint256 operationGas = depositGas + withdrawGas;
            totalGas += operationGas;
            
            if (operationGas > maxGasPerOperation) {
                maxGasPerOperation = operationGas;
            }
        }

        uint256 avgGasPerOperation = totalGas / numOperations;
        
        emit GasUsageRecorded("High Volume Avg Operation", avgGasPerOperation, avgGasPerOperation <= (MAX_DEPOSIT_GAS + MAX_WITHDRAW_GAS));
        emit GasUsageRecorded("High Volume Max Operation", maxGasPerOperation, maxGasPerOperation <= (MAX_DEPOSIT_GAS + MAX_WITHDRAW_GAS));

        assertTrue(avgGasPerOperation <= (MAX_DEPOSIT_GAS + MAX_WITHDRAW_GAS), "High volume operations should remain efficient");
        assertTrue(maxGasPerOperation <= (MAX_DEPOSIT_GAS + MAX_WITHDRAW_GAS) * 12 / 10, "Max gas should not exceed 120% of expected");
    }

    function test_StressTest_LargeDepositAmounts() public {
        uint256 largeAmount = 1_000_000 * 10**6; // 1M USDC
        address user = users[0];
        
        mockUSDC.mint(user, largeAmount);
        
        vm.startPrank(user);
        mockUSDC.approve(address(vault), largeAmount);
        
        uint256 gasStart = gasleft();
        vault.deposit(largeAmount);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Large Deposit", gasUsed, gasUsed <= MAX_DEPOSIT_GAS);
        assertTrue(gasUsed <= MAX_DEPOSIT_GAS, "Large deposits should not use excessive gas");
    }

    // ============ MEMORY OPTIMIZATION TESTS ============

    function test_MemoryOptimization_LargeUserBase() public {
        // Test system performance with large user base
        uint256 numUsers = 100;
        
        // Setup many users
        for (uint256 i = 0; i < numUsers; i++) {
            vm.startPrank(users[i]);
            mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }

        // Test operations still efficient with large user base
        address newUser = makeAddr("newUser");
        mockUSDC.mint(newUser, DEPOSIT_AMOUNT);
        
        vm.startPrank(newUser);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        vault.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Deposit with Large User Base", gasUsed, gasUsed <= MAX_DEPOSIT_GAS);
        assertTrue(gasUsed <= MAX_DEPOSIT_GAS, "Operations should remain efficient with large user base");
    }

    // ============ EDGE CASE GAS TESTS ============

    function test_GasOptimization_MinimumDeposit() public {
        address user = users[0];
        uint256 minDeposit = vault.MINIMUM_DEPOSIT();
        
        vm.startPrank(user);
        mockUSDC.approve(address(vault), minDeposit);
        
        uint256 gasStart = gasleft();
        vault.deposit(minDeposit);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Minimum Deposit", gasUsed, gasUsed <= MAX_DEPOSIT_GAS);
        assertTrue(gasUsed <= MAX_DEPOSIT_GAS, "Minimum deposits should be gas efficient");
    }

    function test_GasOptimization_PartialWithdrawal() public {
        address user = users[0];
        
        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        
        uint256 userShares = vault.userShares(user);
        uint256 partialShares = userShares / 2;
        
        uint256 gasStart = gasleft();
        vault.withdraw(partialShares);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit GasUsageRecorded("Partial Withdrawal", gasUsed, gasUsed <= MAX_WITHDRAW_GAS);
        assertTrue(gasUsed <= MAX_WITHDRAW_GAS, "Partial withdrawals should be gas efficient");
    }
}
