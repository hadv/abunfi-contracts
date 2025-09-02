// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

/**
 * @title DemoRiskBasedSystem
 * @dev Demo script showcasing the risk-based fund management system
 */
contract DemoRiskBasedSystem is Script {
    // Contracts
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    StrategyManager public strategyManager;
    MockERC20 public usdc;

    // Mock strategies
    MockStrategy public aaveStrategy;
    MockStrategy public compoundStrategy;
    MockStrategy public liquidStakingStrategy;

    // Demo users
    address public alice = 0x1111111111111111111111111111111111111111;
    address public bob = 0x2222222222222222222222222222222222222222;
    address public charlie = 0x3333333333333333333333333333333333333333;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== ABUNFI RISK-BASED FUND MANAGEMENT DEMO ===\n");

        // Deploy and setup system
        _deploySystem();
        _setupStrategies();
        _setupRiskAllocations();
        _fundUsers();

        // Demo scenarios
        _demoRiskProfileSelection();
        _demoRiskBasedDeposits();
        _demoYieldGeneration();
        _demoWithdrawals();
        _demoInterestAccrual();

        vm.stopBroadcast();

        console.log("\n=== DEMO COMPLETED SUCCESSFULLY ===");
    }

    function _deploySystem() internal {
        console.log("1. Deploying Risk-Based Fund Management System...");

        // Deploy USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("   USDC deployed at:", address(usdc));

        // Deploy risk management
        riskManager = new RiskProfileManager();
        withdrawalManager = new WithdrawalManager(address(0), address(usdc));
        strategyManager = new StrategyManager(address(riskManager));

        // Deploy vault
        vault = new AbunfiVault(address(usdc), address(0), address(riskManager), address(withdrawalManager));

        console.log("   Core contracts deployed successfully\n");
    }

    function _setupStrategies() internal {
        console.log("2. Setting up Investment Strategies...");

        // Deploy mock strategies with different APYs for demonstration
        aaveStrategy = new MockStrategy(address(usdc), "Aave Lending Strategy", 400); // 4% APY (low risk)
        compoundStrategy = new MockStrategy(address(usdc), "Compound Lending Strategy", 600); // 6% APY (medium risk)
        liquidStakingStrategy = new MockStrategy(address(usdc), "Liquid Staking Strategy", 1200); // 12% APY (high risk)

        // Add strategies to strategy manager
        strategyManager.addStrategy(
            address(aaveStrategy),
            3000, // 30% weight
            20, // 20% risk score (low risk)
            5000, // 50% max allocation
            1000 // 10% min allocation
        );

        strategyManager.addStrategy(
            address(compoundStrategy),
            4000, // 40% weight
            50, // 50% risk score (medium risk)
            6000, // 60% max allocation
            1500 // 15% min allocation
        );

        strategyManager.addStrategy(
            address(liquidStakingStrategy),
            3000, // 30% weight
            80, // 80% risk score (high risk)
            4000, // 40% max allocation
            500 // 5% min allocation
        );

        console.log("   Strategies configured:");
        console.log("   - Aave (Low Risk): 4% APY");
        console.log("   - Compound (Medium Risk): 6% APY");
        console.log("   - Liquid Staking (High Risk): 12% APY\n");
    }

    function _setupRiskAllocations() internal {
        console.log("3. Configuring Risk-Based Allocations...");

        // LOW RISK: Conservative (70% Aave, 30% Compound)
        address[] memory lowRiskStrategies = new address[](2);
        uint256[] memory lowRiskAllocations = new uint256[](2);
        lowRiskStrategies[0] = address(aaveStrategy);
        lowRiskStrategies[1] = address(compoundStrategy);
        lowRiskAllocations[0] = 7000; // 70%
        lowRiskAllocations[1] = 3000; // 30%

        strategyManager.setRiskLevelAllocation(RiskProfileManager.RiskLevel.LOW, lowRiskStrategies, lowRiskAllocations);

        // MEDIUM RISK: Balanced (40% Aave, 40% Compound, 20% Liquid Staking)
        address[] memory mediumRiskStrategies = new address[](3);
        uint256[] memory mediumRiskAllocations = new uint256[](3);
        mediumRiskStrategies[0] = address(aaveStrategy);
        mediumRiskStrategies[1] = address(compoundStrategy);
        mediumRiskStrategies[2] = address(liquidStakingStrategy);
        mediumRiskAllocations[0] = 4000; // 40%
        mediumRiskAllocations[1] = 4000; // 40%
        mediumRiskAllocations[2] = 2000; // 20%

        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.MEDIUM, mediumRiskStrategies, mediumRiskAllocations
        );

        // HIGH RISK: Aggressive (20% Aave, 30% Compound, 50% Liquid Staking)
        address[] memory highRiskStrategies = new address[](3);
        uint256[] memory highRiskAllocations = new uint256[](3);
        highRiskStrategies[0] = address(aaveStrategy);
        highRiskStrategies[1] = address(compoundStrategy);
        highRiskStrategies[2] = address(liquidStakingStrategy);
        highRiskAllocations[0] = 2000; // 20%
        highRiskAllocations[1] = 3000; // 30%
        highRiskAllocations[2] = 5000; // 50%

        strategyManager.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.HIGH, highRiskStrategies, highRiskAllocations
        );

        console.log("   Risk allocations configured:");
        console.log("   - LOW: 70% Aave, 30% Compound");
        console.log("   - MEDIUM: 40% Aave, 40% Compound, 20% Liquid Staking");
        console.log("   - HIGH: 20% Aave, 30% Compound, 50% Liquid Staking\n");
    }

    function _fundUsers() internal {
        console.log("4. Funding Demo Users...");

        // Mint USDC to demo users
        usdc.mint(alice, 10000e6); // $10,000
        usdc.mint(bob, 5000e6); // $5,000
        usdc.mint(charlie, 15000e6); // $15,000

        console.log("   Alice funded with $10,000 USDC");
        console.log("   Bob funded with $5,000 USDC");
        console.log("   Charlie funded with $15,000 USDC\n");
    }

    function _demoRiskProfileSelection() internal {
        console.log("5. Demo: Risk Profile Selection...");

        // Alice chooses LOW risk
        vm.prank(alice);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);
        console.log("   Alice selected LOW risk profile");

        // Bob chooses MEDIUM risk (default)
        console.log("   Bob keeps default MEDIUM risk profile");

        // Charlie chooses HIGH risk
        vm.prank(charlie);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);
        console.log("   Charlie selected HIGH risk profile\n");
    }

    function _demoRiskBasedDeposits() internal {
        console.log("6. Demo: Risk-Based Deposits...");

        // Users approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);

        // Alice deposits $1000 (LOW risk)
        vm.prank(alice);
        vault.deposit(1000e6);
        console.log("   Alice deposited $1,000 (LOW risk allocation)");

        // Bob deposits $2000 (MEDIUM risk)
        vm.prank(bob);
        vault.deposit(2000e6);
        console.log("   Bob deposited $2,000 (MEDIUM risk allocation)");

        // Charlie deposits $5000 (HIGH risk)
        vm.prank(charlie);
        vault.deposit(5000e6);
        console.log("   Charlie deposited $5,000 (HIGH risk allocation)\n");
    }

    function _demoYieldGeneration() internal {
        console.log("7. Demo: Yield Generation (Simulating 30 days)...");

        // Simulate 30 days passing
        vm.warp(block.timestamp + 30 days);

        // Simulate yield generation in strategies using MockStrategy's addYield function
        uint256 aaveYield = aaveStrategy.totalAssets() * 400 / 10000 / 12; // Monthly yield
        uint256 compoundYield = compoundStrategy.totalAssets() * 600 / 10000 / 12;
        uint256 liquidStakingYield = liquidStakingStrategy.totalAssets() * 1200 / 10000 / 12;

        aaveStrategy.addYield(aaveYield);
        compoundStrategy.addYield(compoundYield);
        liquidStakingStrategy.addYield(liquidStakingYield);

        console.log("   30 days passed - yield generated in all strategies");
        console.log("   Users can now see accrued interest\n");
    }

    function _demoWithdrawals() internal {
        console.log("8. Demo: Withdrawal System...");

        // Alice requests withdrawal (with window period)
        uint256 aliceShares = vault.userShares(alice);
        vm.prank(alice);
        uint256 requestId = vault.requestWithdrawal(aliceShares / 2);
        console.log("   Alice requested withdrawal of 50% of her shares (Request ID:", requestId, ")");

        // Bob does instant withdrawal (with fee)
        uint256 bobShares = vault.userShares(bob);
        vm.prank(bob);
        vault.instantWithdrawal(bobShares / 4);
        console.log("   Bob performed instant withdrawal of 25% of his shares (with fee)");

        // Simulate withdrawal window passing
        vm.warp(block.timestamp + 7 days + 1);

        // Alice processes her withdrawal
        vm.prank(alice);
        vault.processWithdrawal(requestId);
        console.log("   Alice processed her withdrawal after window period (no fee)\n");
    }

    function _demoInterestAccrual() internal {
        console.log("9. Demo: Interest Accrual Tracking...");

        // Interest is automatically updated when users interact with the vault
        // For demo purposes, we'll just show the current accrued interest

        uint256 aliceInterest = vault.getUserAccruedInterest(alice);
        uint256 bobInterest = vault.getUserAccruedInterest(bob);
        uint256 charlieInterest = vault.getUserAccruedInterest(charlie);

        console.log("   Interest accrued:");
        console.log("   - Alice (LOW risk):", aliceInterest / 1e6, "USDC");
        console.log("   - Bob (MEDIUM risk):", bobInterest / 1e6, "USDC");
        console.log("   - Charlie (HIGH risk):", charlieInterest / 1e6, "USDC");

        console.log("\n   Charlie (high risk) should have earned the most interest");
        console.log("   Alice (low risk) should have earned the least interest");
    }
}
