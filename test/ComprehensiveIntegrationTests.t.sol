// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/StrategyManager.sol";

/**
 * @title ComprehensiveIntegrationTests
 * @dev End-to-end integration tests combining multiple edge cases and stress scenarios
 * Simulates real-world production conditions with multiple concurrent issues
 */
contract ComprehensiveIntegrationTestsTest is Test {
    // Core contracts
    AbunfiVault public vault;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;
    StrategyManager public strategyManager;
    MockERC20 public mockUSDC;

    // Strategies
    AaveStrategy public aaveStrategy;
    CompoundStrategy public compoundStrategy;

    // Mock external protocols
    MockAavePool public mockAavePool;
    MockAaveDataProvider public mockAaveDataProvider;
    MockComet public mockComet;
    MockCometRewards public mockCometRewards;

    // Test participants
    address public owner;
    address public whale; // Large depositor
    address public retailUser1;
    address public retailUser2;
    address public attacker;
    address public liquidator;

    // Test constants
    uint256 constant WHALE_DEPOSIT = 10_000_000 * 10**6; // 10M USDC
    uint256 constant RETAIL_DEPOSIT = 10_000 * 10**6; // 10k USDC
    uint256 constant ATTACK_AMOUNT = 1_000_000 * 10**6; // 1M USDC

    event SystemStressTest(string scenario, bool passed, string details);
    event MarketCrashSimulation(uint256 totalLoss, uint256 usersAffected);
    event RecoveryTest(uint256 recoveryTime, bool successful);

    function setUp() public {
        owner = address(this);
        whale = makeAddr("whale");
        retailUser1 = makeAddr("retailUser1");
        retailUser2 = makeAddr("retailUser2");
        attacker = makeAddr("attacker");
        liquidator = makeAddr("liquidator");

        _deployContracts();
        _setupStrategies();
        _fundUsers();
    }

    function _deployContracts() internal {
        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy mock external protocols
        MockERC20 mockAUSDC = new MockERC20("Aave interest bearing USDC", "aUSDC", 6);
        mockAavePool = new MockAavePool(address(mockUSDC));
        mockAaveDataProvider = new MockAaveDataProvider();
        mockComet = new MockComet(address(mockUSDC));
        mockCometRewards = new MockCometRewards();

        // Setup Aave mocks
        mockAavePool.setAToken(address(mockUSDC), address(mockAUSDC));
        mockAaveDataProvider.setReserveTokens(address(mockUSDC), address(mockAUSDC), address(0), address(0));
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 5e25); // 5% APY

        // Deploy core system
        riskManager = new RiskProfileManager();
        withdrawalManager = new WithdrawalManager(address(0), address(mockUSDC));
        strategyManager = new StrategyManager(address(riskManager));

        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(withdrawalManager)
        );
    }

    function _setupStrategies() internal {
        // Deploy strategies
        aaveStrategy = new AaveStrategy(
            address(mockUSDC),
            address(mockAavePool),
            address(mockAaveDataProvider),
            address(vault)
        );

        compoundStrategy = new CompoundStrategy(
            address(mockUSDC),
            address(mockComet),
            address(mockCometRewards),
            address(vault)
        );

        // Add strategies to vault
        vault.addStrategy(address(aaveStrategy));
        vault.addStrategy(address(compoundStrategy));
    }

    function _fundUsers() internal {
        mockUSDC.mint(whale, WHALE_DEPOSIT * 2);
        mockUSDC.mint(retailUser1, RETAIL_DEPOSIT * 2);
        mockUSDC.mint(retailUser2, RETAIL_DEPOSIT * 2);
        mockUSDC.mint(attacker, ATTACK_AMOUNT * 2);
        mockUSDC.mint(liquidator, ATTACK_AMOUNT);
    }

    // ============ COMPREHENSIVE STRESS TEST SCENARIOS ============

    function test_ComprehensiveStress_MarketCrashWithBankRun() public {
        // Phase 1: Normal operations - users deposit
        _setupNormalOperations();

        // Phase 2: Market crash simulation
        _simulateMarketCrash();

        // Phase 3: Bank run simulation
        bool bankRunHandled = _simulateBankRun();

        // Phase 4: System recovery
        bool systemRecovered = _testSystemRecovery();

        emit SystemStressTest(
            "Market Crash + Bank Run",
            bankRunHandled && systemRecovered,
            "Combined stress test of market crash and mass withdrawals"
        );

        assertTrue(bankRunHandled, "System should handle bank run during market crash");
        assertTrue(systemRecovered, "System should recover after stress events");
    }

    function test_ComprehensiveStress_AttackDuringVolatility() public {
        // Setup normal operations
        _setupNormalOperations();

        // Simulate high volatility
        _simulateHighVolatility();

        // Execute economic attack during volatility
        bool attackMitigated = _executeEconomicAttackDuringVolatility();

        // Test system integrity
        bool integrityMaintained = _verifySystemIntegrity();

        emit SystemStressTest(
            "Attack During Volatility",
            attackMitigated && integrityMaintained,
            "Economic attack during high market volatility"
        );

        assertTrue(attackMitigated, "Economic attacks should be mitigated");
        assertTrue(integrityMaintained, "System integrity should be maintained");
    }

    function test_ComprehensiveStress_MultipleStrategyFailures() public {
        // Setup with multiple strategies
        _setupNormalOperations();

        // Simulate multiple strategy failures
        bool failuresHandled = _simulateMultipleStrategyFailures();

        // Test emergency procedures
        bool emergencyHandled = _testEmergencyProcedures();

        // Verify user fund safety
        bool fundsProtected = _verifyUserFundProtection();

        emit SystemStressTest(
            "Multiple Strategy Failures",
            failuresHandled && emergencyHandled && fundsProtected,
            "Cascading strategy failures with emergency response"
        );

        assertTrue(failuresHandled, "Strategy failures should be handled gracefully");
        assertTrue(emergencyHandled, "Emergency procedures should work");
        assertTrue(fundsProtected, "User funds should be protected");
    }

    // ============ HELPER FUNCTIONS FOR STRESS SCENARIOS ============

    function _setupNormalOperations() internal {
        // Whale deposits
        vm.startPrank(whale);
        mockUSDC.approve(address(vault), WHALE_DEPOSIT);
        vault.deposit(WHALE_DEPOSIT);
        vm.stopPrank();

        // Retail users deposit
        vm.startPrank(retailUser1);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.LOW);
        mockUSDC.approve(address(vault), RETAIL_DEPOSIT);
        vault.deposit(RETAIL_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(retailUser2);
        riskManager.setRiskProfile(RiskProfileManager.RiskLevel.HIGH);
        mockUSDC.approve(address(vault), RETAIL_DEPOSIT);
        vault.deposit(RETAIL_DEPOSIT);
        vm.stopPrank();
    }

    function _simulateMarketCrash() internal {
        // Simulate 30% market crash affecting all strategies
        mockAavePool.setLiquidityCrisis(true);
        mockComet.setSupplyRate(0); // Zero yield
        
        // Strategies lose value
        vm.prank(address(vault));
        mockUSDC.transfer(owner, vault.totalAssets() * 30 / 100); // 30% loss simulation

        emit MarketCrashSimulation(vault.totalAssets() * 30 / 100, 3);
    }

    function _simulateBankRun() internal returns (bool) {
        try this._executeBankRun() {
            return true;
        } catch {
            return false;
        }
    }

    function _executeBankRun() external {
        // All users try to withdraw simultaneously
        vm.startPrank(whale);
        uint256 whaleShares = vault.userShares(whale);
        vault.requestWithdrawal(whaleShares);
        vm.stopPrank();

        vm.startPrank(retailUser1);
        uint256 user1Shares = vault.userShares(retailUser1);
        vault.requestWithdrawal(user1Shares);
        vm.stopPrank();

        vm.startPrank(retailUser2);
        uint256 user2Shares = vault.userShares(retailUser2);
        vault.requestWithdrawal(user2Shares);
        vm.stopPrank();
    }

    function _simulateHighVolatility() internal {
        // Rapid price swings
        for (uint256 i = 0; i < 10; i++) {
            if (i % 2 == 0) {
                // Positive swing
                mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 10e25); // 10% APY
            } else {
                // Negative swing
                mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 1e25); // 1% APY
            }
        }
    }

    function _executeEconomicAttackDuringVolatility() internal returns (bool) {
        try this._performSandwichAttack() {
            return false; // Attack succeeded - bad
        } catch {
            return true; // Attack failed - good
        }
    }

    function _performSandwichAttack() external {
        // Attacker tries sandwich attack during volatility
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), ATTACK_AMOUNT);
        
        // Front-run
        vault.deposit(ATTACK_AMOUNT);
        
        // Back-run (immediate withdrawal)
        uint256 attackerShares = vault.userShares(attacker);
        vault.withdraw(attackerShares);
        
        vm.stopPrank();
    }

    function _simulateMultipleStrategyFailures() internal returns (bool) {
        try this._causeStrategyFailures() {
            return true;
        } catch {
            return false;
        }
    }

    function _causeStrategyFailures() external {
        // Aave strategy fails
        mockAavePool.setLiquidityCrisis(true);
        
        // Compound strategy fails
        mockComet.setSupplyRate(0);
        
        // Try to harvest - should handle failures gracefully
        vm.prank(address(vault));
        aaveStrategy.harvest();
        
        vm.prank(address(vault));
        compoundStrategy.harvest();
    }

    function _testEmergencyProcedures() internal returns (bool) {
        try this._executeEmergencyProcedures() {
            return true;
        } catch {
            return false;
        }
    }

    function _executeEmergencyProcedures() external {
        // Pause the vault
        vault.pause();
        
        // Emergency withdrawal from strategies
        vm.prank(address(vault));
        aaveStrategy.withdrawAll();
        
        vm.prank(address(vault));
        compoundStrategy.withdrawAll();
        
        // Unpause
        vault.unpause();
    }

    function _testSystemRecovery() internal returns (bool) {
        // Fast forward past withdrawal windows
        vm.warp(block.timestamp + 8 days);
        
        try this._processRecovery() {
            return true;
        } catch {
            return false;
        }
    }

    function _processRecovery() external {
        // Process pending withdrawals
        vm.prank(whale);
        vault.processWithdrawal(0);
        
        vm.prank(retailUser1);
        vault.processWithdrawal(0);
        
        vm.prank(retailUser2);
        vault.processWithdrawal(0);
        
        emit RecoveryTest(8 days, true);
    }

    function _verifySystemIntegrity() internal returns (bool) {
        // Check that basic operations still work
        try this._testBasicOperations() {
            return true;
        } catch {
            return false;
        }
    }

    function _testBasicOperations() external {
        address newUser = makeAddr("newUser");
        mockUSDC.mint(newUser, RETAIL_DEPOSIT);
        
        vm.startPrank(newUser);
        mockUSDC.approve(address(vault), RETAIL_DEPOSIT);
        vault.deposit(RETAIL_DEPOSIT);
        
        uint256 userShares = vault.userShares(newUser);
        vault.withdraw(userShares);
        vm.stopPrank();
    }

    function _verifyUserFundProtection() internal returns (bool) {
        // Check that users can still recover reasonable amounts
        uint256 whaleBalance = mockUSDC.balanceOf(whale);
        uint256 user1Balance = mockUSDC.balanceOf(retailUser1);
        uint256 user2Balance = mockUSDC.balanceOf(retailUser2);
        
        // Users should recover at least 70% of their deposits in worst case
        bool whaleProtected = whaleBalance >= WHALE_DEPOSIT * 70 / 100;
        bool user1Protected = user1Balance >= RETAIL_DEPOSIT * 70 / 100;
        bool user2Protected = user2Balance >= RETAIL_DEPOSIT * 70 / 100;
        
        return whaleProtected && user1Protected && user2Protected;
    }

    // ============ LONG-TERM STABILITY TESTS ============

    function test_LongTermStability_ExtendedOperations() public {
        // Simulate 1 year of operations
        uint256 timeStep = 30 days; // Monthly operations
        uint256 totalTime = 365 days;
        
        _setupNormalOperations();
        
        for (uint256 time = 0; time < totalTime; time += timeStep) {
            vm.warp(block.timestamp + timeStep);
            
            // Monthly yield generation
            vm.prank(address(vault));
            aaveStrategy.harvest();
            
            vm.prank(address(vault));
            compoundStrategy.harvest();
            
            // Some users deposit/withdraw monthly
            if (time % (timeStep * 2) == 0) {
                _simulateMonthlyActivity();
            }
        }
        
        // Verify system stability after extended operations
        assertTrue(vault.totalShares() > 0, "System should remain stable long-term");
        assertTrue(vault.totalDeposits() > 0, "Deposits should be maintained long-term");
    }

    function _simulateMonthlyActivity() internal {
        address monthlyUser = makeAddr(string(abi.encodePacked("monthly", block.timestamp)));
        mockUSDC.mint(monthlyUser, RETAIL_DEPOSIT);
        
        vm.startPrank(monthlyUser);
        mockUSDC.approve(address(vault), RETAIL_DEPOSIT);
        vault.deposit(RETAIL_DEPOSIT);
        vm.stopPrank();
    }

    // ============ EDGE CASE COMBINATIONS ============

    function test_EdgeCaseCombination_ZeroLiquidityWithAttack() public {
        // Setup minimal liquidity
        vm.startPrank(retailUser1);
        mockUSDC.approve(address(vault), vault.MINIMUM_DEPOSIT());
        vault.deposit(vault.MINIMUM_DEPOSIT());
        vm.stopPrank();

        // Drain most liquidity
        uint256 vaultBalance = mockUSDC.balanceOf(address(vault));
        vm.prank(address(vault));
        mockUSDC.transfer(owner, vaultBalance * 99 / 100);

        // Attacker tries to exploit low liquidity
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), vault.MINIMUM_DEPOSIT());
        
        try vault.deposit(vault.MINIMUM_DEPOSIT()) {
            // If deposit succeeds, try immediate withdrawal
            uint256 attackerShares = vault.userShares(attacker);
            vault.withdraw(attackerShares);
        } catch {
            // Expected behavior - system should protect against this
        }
        vm.stopPrank();

        // System should still function for legitimate users
        assertTrue(vault.userShares(retailUser1) > 0, "Legitimate users should be protected");
    }
}
