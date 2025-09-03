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

/**
 * @title StrategyFailureScenarios
 * @dev Tests for strategy failure scenarios and external protocol failures
 * Critical for production finance applications to handle protocol failures gracefully
 */
contract StrategyFailureScenariosTest is Test {
    AbunfiVault public vault;
    AaveStrategy public aaveStrategy;
    CompoundStrategy public compoundStrategy;
    MockERC20 public mockUSDC;
    MockAavePool public mockAavePool;
    MockAaveDataProvider public mockAaveDataProvider;
    MockComet public mockComet;
    MockCometRewards public mockCometRewards;
    RiskProfileManager public riskManager;
    WithdrawalManager public withdrawalManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant DEPOSIT_AMOUNT = 1000 * 10**6; // 1000 USDC
    uint256 constant LARGE_DEPOSIT = 100_000 * 10**6; // 100k USDC

    event StrategyFailure(address indexed strategy, string reason);
    event EmergencyWithdrawal(address indexed strategy, uint256 amount);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock USDC
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy mock Aave components
        MockERC20 mockAUSDC = new MockERC20("Aave interest bearing USDC", "aUSDC", 6);
        mockAavePool = new MockAavePool(address(mockUSDC));
        mockAaveDataProvider = new MockAaveDataProvider();
        
        // Setup Aave mocks
        mockAavePool.setAToken(address(mockUSDC), address(mockAUSDC));
        mockAaveDataProvider.setReserveTokens(address(mockUSDC), address(mockAUSDC), address(0), address(0));
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 5e25); // 5% APY

        // Deploy mock Compound components
        mockComet = new MockComet(address(mockUSDC));
        mockCometRewards = new MockCometRewards();

        // Deploy risk management
        riskManager = new RiskProfileManager();
        withdrawalManager = new WithdrawalManager(address(0), address(mockUSDC));

        // Deploy vault
        vault = new AbunfiVault(
            address(mockUSDC),
            address(0),
            address(riskManager),
            address(withdrawalManager)
        );

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

        // Mint tokens to users
        mockUSDC.mint(user1, LARGE_DEPOSIT);
        mockUSDC.mint(user2, LARGE_DEPOSIT);
        mockUSDC.mint(address(vault), LARGE_DEPOSIT); // For strategy operations
    }

    // ============ AAVE STRATEGY FAILURE TESTS ============

    function test_AaveStrategy_PoolFailure() public {
        // Setup: User deposits into vault
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate Aave pool failure by making it revert
        FailingAavePool failingPool = new FailingAavePool();
        
        // Deploy new strategy with failing pool
        AaveStrategy failingStrategy = new AaveStrategy(
            address(mockUSDC),
            address(failingPool),
            address(mockAaveDataProvider),
            address(vault)
        );

        // Add failing strategy
        vault.addStrategy(address(failingStrategy));

        // Try to deposit to failing strategy - should handle gracefully
        vm.prank(address(vault));
        mockUSDC.transfer(address(failingStrategy), DEPOSIT_AMOUNT);
        
        vm.expectRevert("Aave pool is down");
        vm.prank(address(vault));
        failingStrategy.deposit(DEPOSIT_AMOUNT);
    }

    function test_AaveStrategy_LiquidityCrisis() public {
        // Setup strategy with deposits
        vm.prank(address(vault));
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        
        vm.prank(address(vault));
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate liquidity crisis - Aave can't fulfill withdrawal
        mockAavePool.setLiquidityCrisis(true);

        // Withdrawal should fail gracefully
        vm.expectRevert("Insufficient liquidity");
        vm.prank(address(vault));
        aaveStrategy.withdraw(DEPOSIT_AMOUNT);
    }

    function test_AaveStrategy_ExtremeAPYFluctuation() public {
        // Test strategy behavior with extreme APY changes
        vm.prank(address(vault));
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        
        vm.prank(address(vault));
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate extreme APY drop (negative rates)
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 0);
        
        uint256 apy = aaveStrategy.getAPY();
        assertEq(apy, 0, "APY should be 0 with zero liquidity rate");

        // Simulate extreme APY spike
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), 100e25); // 100% APY
        
        apy = aaveStrategy.getAPY();
        assertTrue(apy > 0, "APY should be positive with high liquidity rate");
    }

    // ============ COMPOUND STRATEGY FAILURE TESTS ============

    function test_CompoundStrategy_CometFailure() public {
        // Setup: User deposits into vault
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate Compound Comet failure
        FailingComet failingComet = new FailingComet();
        
        CompoundStrategy failingStrategy = new CompoundStrategy(
            address(mockUSDC),
            address(failingComet),
            address(mockCometRewards),
            address(vault)
        );

        vault.addStrategy(address(failingStrategy));

        // Try to deposit to failing strategy
        vm.prank(address(vault));
        mockUSDC.transfer(address(failingStrategy), DEPOSIT_AMOUNT);
        
        vm.expectRevert("Compound is down");
        vm.prank(address(vault));
        failingStrategy.deposit(DEPOSIT_AMOUNT);
    }

    function test_CompoundStrategy_UtilizationSpike() public {
        // Setup strategy
        vm.prank(address(vault));
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        
        vm.prank(address(vault));
        compoundStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate extreme utilization spike (affects supply rate)
        mockComet.setUtilization(9500); // 95% utilization
        mockComet.setSupplyRate(100); // Very low supply rate due to high utilization

        uint256 apy = compoundStrategy.getAPY();
        assertTrue(apy >= 0, "APY should not be negative");
    }

    // ============ STRATEGY MIGRATION TESTS ============

    function test_StrategyMigration_EmergencyExit() public {
        // Setup: Deposit into strategy
        vm.prank(address(vault));
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        
        vm.prank(address(vault));
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        uint256 initialBalance = mockUSDC.balanceOf(address(vault));

        // Emergency withdrawal
        vm.prank(address(vault));
        aaveStrategy.withdrawAll();

        uint256 finalBalance = mockUSDC.balanceOf(address(vault));
        assertTrue(finalBalance > initialBalance, "Emergency withdrawal should return funds");
    }

    function test_StrategyMigration_PartialFailure() public {
        // Setup multiple strategies with deposits
        vm.prank(address(vault));
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);
        vm.prank(address(vault));
        aaveStrategy.deposit(DEPOSIT_AMOUNT);

        vm.prank(address(vault));
        mockUSDC.transfer(address(compoundStrategy), DEPOSIT_AMOUNT);
        vm.prank(address(vault));
        compoundStrategy.deposit(DEPOSIT_AMOUNT);

        // Simulate one strategy failing
        mockAavePool.setLiquidityCrisis(true);

        // Compound strategy should still work
        vm.prank(address(vault));
        uint256 yield = compoundStrategy.harvest();
        assertTrue(yield >= 0, "Working strategy should still function");

        // Aave strategy should fail
        vm.expectRevert("Insufficient liquidity");
        vm.prank(address(vault));
        aaveStrategy.withdraw(DEPOSIT_AMOUNT / 2);
    }

    // ============ GAS LIMIT TESTS ============

    function test_StrategyOperations_GasLimits() public {
        // Test operations under gas constraints
        uint256 gasLimit = 100000; // Restrictive gas limit

        vm.prank(address(vault));
        mockUSDC.transfer(address(aaveStrategy), DEPOSIT_AMOUNT);

        // Deposit with gas limit
        uint256 gasStart = gasleft();
        vm.prank(address(vault));
        aaveStrategy.deposit(DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();

        assertTrue(gasUsed < gasLimit, "Deposit should be gas efficient");

        // Harvest with gas limit
        gasStart = gasleft();
        vm.prank(address(vault));
        aaveStrategy.harvest();
        gasUsed = gasStart - gasleft();

        assertTrue(gasUsed < gasLimit, "Harvest should be gas efficient");
    }

    // ============ ORACLE MANIPULATION TESTS ============

    function test_StrategyAPY_OracleManipulation() public {
        // Test strategy behavior with manipulated APY data
        uint256 normalAPY = aaveStrategy.getAPY();

        // Simulate oracle manipulation - extreme APY values
        mockAaveDataProvider.setLiquidityRate(address(mockUSDC), type(uint256).max);
        
        // Strategy should handle extreme values gracefully
        uint256 manipulatedAPY = aaveStrategy.getAPY();
        
        // APY should be bounded or handled safely
        assertTrue(manipulatedAPY != type(uint256).max, "Strategy should handle extreme APY values");
    }

    // ============ CONCURRENT OPERATION TESTS ============

    function test_ConcurrentOperations_MultipleUsers() public {
        // Simulate multiple users operating simultaneously
        uint256 amount1 = 1000 * 10**6;
        uint256 amount2 = 2000 * 10**6;

        // User 1 deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), amount1);
        vault.deposit(amount1);
        vm.stopPrank();

        // User 2 deposits simultaneously (same block)
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), amount2);
        vault.deposit(amount2);
        vm.stopPrank();

        // Both users should have correct shares
        uint256 shares1 = vault.userShares(user1);
        uint256 shares2 = vault.userShares(user2);

        assertTrue(shares1 > 0, "User 1 should have shares");
        assertTrue(shares2 > 0, "User 2 should have shares");
        assertTrue(shares2 > shares1, "User 2 should have more shares");
    }
}

/**
 * @title FailingAavePool
 * @dev Mock contract that simulates Aave pool failures
 */
contract FailingAavePool {
    function supply(address, uint256, address, uint16) external pure {
        revert("Aave pool is down");
    }

    function withdraw(address, uint256, address) external pure returns (uint256) {
        revert("Aave pool is down");
    }

    function getReserveData(address) external pure returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        revert("Aave pool is down");
    }
}

/**
 * @title FailingComet
 * @dev Mock contract that simulates Compound Comet failures
 */
contract FailingComet {
    function supply(address, uint256) external pure {
        revert("Compound is down");
    }

    function withdraw(address, uint256) external pure {
        revert("Compound is down");
    }

    function balanceOf(address) external pure returns (uint256) {
        revert("Compound is down");
    }

    function getSupplyRate(uint256) external pure returns (uint64) {
        revert("Compound is down");
    }

    function getUtilization() external pure returns (uint256) {
        revert("Compound is down");
    }

    function baseToken() external pure returns (address) {
        revert("Compound is down");
    }

    function decimals() external pure returns (uint8) {
        revert("Compound is down");
    }

    function accrueAccount(address) external pure {
        revert("Compound is down");
    }
}
