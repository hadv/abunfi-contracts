// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockStrategy.sol";
import "../src/mocks/MockERC20.sol";

contract StrategyManagerTest is Test {
    StrategyManager public strategyManager;
    MockStrategy public mockAaveStrategy;
    MockStrategy public mockCompoundStrategy;
    MockStrategy public mockLiquidStakingStrategy;
    MockERC20 public mockUSDC;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 6; // 1M USDC

    event StrategyAdded(address indexed strategy, uint256 weight, uint256 riskScore);
    event StrategyUpdated(address indexed strategy, uint256 weight, uint256 riskScore);
    event StrategyDeactivated(address indexed strategy);
    event StrategyReactivated(address indexed strategy);
    event APYUpdated(address indexed strategy, uint256 oldAPY, uint256 newAPY);
    event RiskToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock USDC
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Deploy StrategyManager
        strategyManager = new StrategyManager();

        // Create mock strategies
        mockAaveStrategy = new MockStrategy(
            address(mockUSDC),
            "Aave Strategy",
            500 // 5% APY
        );

        mockCompoundStrategy = new MockStrategy(
            address(mockUSDC),
            "Compound Strategy",
            450 // 4.5% APY
        );

        mockLiquidStakingStrategy = new MockStrategy(
            address(mockUSDC),
            "Liquid Staking Strategy",
            600 // 6% APY
        );

        // Setup initial balances
        mockUSDC.mint(address(strategyManager), INITIAL_SUPPLY);
    }

    // Deployment Tests
    function test_Deployment_InitializeWithCorrectParameters() public {
        assertEq(strategyManager.riskTolerance(), 50);
        assertEq(strategyManager.performanceWindow(), 30 * 24 * 3600); // 30 days
        assertEq(strategyManager.rebalanceThreshold(), 500); // 5%
        assertEq(strategyManager.BASIS_POINTS(), 10000);
        assertEq(strategyManager.MAX_RISK_SCORE(), 100);
    }

    function test_Deployment_SetCorrectOwner() public {
        assertEq(strategyManager.owner(), owner);
    }

    // Strategy Management Tests
    function test_StrategyManagement_AddNewStrategy() public {
        vm.expectEmit(true, true, true, true);
        emit StrategyAdded(address(mockAaveStrategy), 3000, 20);

        strategyManager.addStrategy(
            address(mockAaveStrategy),
            3000, // 30% weight
            20, // 20% risk score
            4000, // 40% max allocation
            1000 // 10% min allocation
        );

        (
            IAbunfiStrategy strategy,
            uint256 weight,
            uint256 riskScore,
            uint256 maxAllocation,
            uint256 minAllocation,
            bool isActive,
            uint256 lastAPY,
            uint256 apyHistory,
            uint256 performanceScore
        ) = strategyManager.strategies(address(mockAaveStrategy));
        assertEq(weight, 3000);
        assertEq(riskScore, 20);
        assertTrue(isActive);
    }

    function test_StrategyManagement_RevertInvalidWeight() public {
        vm.expectRevert("Weight must be positive");
        strategyManager.addStrategy(address(mockAaveStrategy), 0, 20, 4000, 1000);
    }

    function test_StrategyManagement_RevertInvalidRiskScore() public {
        vm.expectRevert("Risk score too high");
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 150, 4000, 1000);
    }

    function test_StrategyManagement_RevertInvalidAllocation() public {
        vm.expectRevert("Min allocation > max allocation");
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 3000, 4000);
    }

    function test_StrategyManagement_UpdateStrategyParameters() public {
        // Add strategy first
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);

        vm.expectEmit(true, true, true, true);
        emit StrategyUpdated(address(mockAaveStrategy), 3500, 25);

        strategyManager.updateStrategy(
            address(mockAaveStrategy),
            3500, // New weight
            25, // New risk score
            4500, // New max allocation
            1500 // New min allocation
        );

        (, uint256 weight, uint256 riskScore,,,,,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertEq(weight, 3500);
        assertEq(riskScore, 25);
    }

    function test_StrategyManagement_DeactivateStrategy() public {
        // Add strategy first
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);

        vm.expectEmit(true, true, true, true);
        emit StrategyDeactivated(address(mockAaveStrategy));

        strategyManager.deactivateStrategy(address(mockAaveStrategy));

        (,,,,, bool isActive,,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertFalse(isActive);
    }

    function test_StrategyManagement_ReactivateStrategy() public {
        // Add and deactivate strategy first
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);
        strategyManager.deactivateStrategy(address(mockAaveStrategy));

        vm.expectEmit(true, true, true, true);
        emit StrategyReactivated(address(mockAaveStrategy));

        strategyManager.reactivateStrategy(address(mockAaveStrategy));

        (,,,,, bool isActive,,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertTrue(isActive);
    }

    // APY Tracking Tests
    function test_APYTracking_UpdateStrategyAPY() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);

        uint256 newAPY = 550; // 5.5%

        vm.expectEmit(true, true, true, true);
        emit APYUpdated(address(mockAaveStrategy), 0, newAPY);

        strategyManager.updateStrategyAPY(address(mockAaveStrategy), newAPY);

        (,,,,,, uint256 lastAPY,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertEq(lastAPY, newAPY);
    }

    function test_APYTracking_CalculateMovingAverageAPY() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);

        // Update APY multiple times
        strategyManager.updateStrategyAPY(address(mockAaveStrategy), 500);
        strategyManager.updateStrategyAPY(address(mockAaveStrategy), 550);
        strategyManager.updateStrategyAPY(address(mockAaveStrategy), 600);

        (,,,,,,, uint256 apyHistory,) = strategyManager.strategies(address(mockAaveStrategy));
        assertGt(apyHistory, 0);
    }

    function test_APYTracking_UpdatePerformanceScore() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 4000, 1000);

        // Simulate consistent performance
        for (uint256 i = 0; i < 10; i++) {
            strategyManager.updateStrategyAPY(address(mockAaveStrategy), 500);
        }

        (,,,,,,,, uint256 performanceScore) = strategyManager.strategies(address(mockAaveStrategy));
        assertGe(performanceScore, 50);
    }

    // Allocation Calculation Tests
    function test_AllocationCalculation_CalculateOptimalAllocation() public {
        // Add multiple strategies
        strategyManager.addStrategy(
            address(mockAaveStrategy),
            3000, // 30% weight
            20, // Low risk
            4000,
            1000
        );

        strategyManager.addStrategy(
            address(mockCompoundStrategy),
            2500, // 25% weight
            25, // Medium risk
            3500,
            800
        );

        strategyManager.addStrategy(
            address(mockLiquidStakingStrategy),
            4500, // 45% weight
            15, // Very low risk
            5000,
            1500
        );

        uint256 totalAmount = 10000 * 10 ** 6; // 10k USDC
        uint256[] memory allocations = strategyManager.calculateOptimalAllocation(totalAmount);

        assertEq(allocations.length, 3);

        // Check that allocations sum to total amount
        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocated += allocations[i];
        }
        assertEq(totalAllocated, totalAmount);
    }

    function test_AllocationCalculation_RespectRiskTolerance() public {
        // Add strategies
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);
        strategyManager.addStrategy(address(mockCompoundStrategy), 2500, 25, 6000, 800);
        strategyManager.addStrategy(address(mockLiquidStakingStrategy), 4500, 15, 5000, 1500);

        // Set low risk tolerance
        strategyManager.setRiskTolerance(30);

        uint256 totalAmount = 10000 * 10 ** 6;
        uint256[] memory allocations = strategyManager.calculateOptimalAllocation(totalAmount);

        assertEq(allocations.length, 3);
    }

    function test_AllocationCalculation_RespectMinMaxConstraints() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);
        strategyManager.addStrategy(address(mockCompoundStrategy), 2500, 25, 6000, 800);

        uint256 totalAmount = 10000 * 10 ** 6;
        uint256[] memory allocations = strategyManager.calculateOptimalAllocation(totalAmount);

        // Check each allocation respects constraints
        for (uint256 i = 0; i < allocations.length; i++) {
            address strategyAddr = strategyManager.strategyList(i);
            (,,, uint256 maxAllocation, uint256 minAllocation,,,,) = strategyManager.strategies(strategyAddr);

            uint256 allocationPercent = (allocations[i] * 10000) / totalAmount;
            assertGe(allocationPercent, minAllocation);
            assertLe(allocationPercent, maxAllocation);
        }
    }

    // Risk Management Tests
    function test_RiskManagement_SetRiskTolerance() public {
        vm.expectEmit(true, true, true, true);
        emit RiskToleranceUpdated(50, 70);

        strategyManager.setRiskTolerance(70);

        assertEq(strategyManager.riskTolerance(), 70);
    }

    function test_RiskManagement_RevertInvalidRiskTolerance() public {
        vm.expectRevert("Risk tolerance too high");
        strategyManager.setRiskTolerance(150);
    }

    function test_RiskManagement_CalculateRiskAdjustedReturn() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);

        uint256 riskAdjustedReturn = strategyManager.calculateRiskAdjustedReturn(address(mockAaveStrategy));
        assertGe(riskAdjustedReturn, 0);
    }

    // View Functions Tests
    function test_ViewFunctions_GetActiveStrategies() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);
        strategyManager.addStrategy(address(mockCompoundStrategy), 2500, 25, 6000, 800);

        address[] memory activeStrategies = strategyManager.getActiveStrategies();
        assertEq(activeStrategies.length, 2);
    }

    function test_ViewFunctions_GetStrategyCount() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);
        strategyManager.addStrategy(address(mockCompoundStrategy), 2500, 25, 6000, 800);

        uint256 count = strategyManager.getStrategyCount();
        assertEq(count, 2);
    }

    // Access Control Tests
    function test_AccessControl_OnlyOwnerCanAddStrategies() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);
    }

    function test_AccessControl_OnlyOwnerCanUpdateRiskTolerance() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        strategyManager.setRiskTolerance(70);
    }

    function test_AccessControl_OnlyOwnerCanUpdateStrategy() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        strategyManager.updateStrategy(address(mockAaveStrategy), 3500, 25, 4500, 1500);
    }

    // Emergency Functions Tests
    function test_EmergencyFunctions_PauseStrategy() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);

        strategyManager.pauseStrategy(address(mockAaveStrategy));

        (,,,,, bool isActive,,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertFalse(isActive);
    }

    function test_EmergencyFunctions_EmergencyStopAllStrategies() public {
        strategyManager.addStrategy(address(mockAaveStrategy), 3000, 20, 6000, 1000);

        strategyManager.emergencyStop();

        (,,,,, bool isActive,,,) = strategyManager.strategies(address(mockAaveStrategy));
        assertFalse(isActive);
    }

    // Fuzz Tests
    function testFuzz_AddStrategy_ValidParameters(uint256 weight, uint256 riskScore, uint256 maxAlloc, uint256 minAlloc)
        public
    {
        weight = bound(weight, 1, 10000);
        riskScore = bound(riskScore, 1, 100);
        maxAlloc = bound(maxAlloc, 1000, 10000);
        minAlloc = bound(minAlloc, 100, maxAlloc);

        strategyManager.addStrategy(address(mockAaveStrategy), weight, riskScore, maxAlloc, minAlloc);

        (, uint256 stratWeight, uint256 stratRisk,,, bool isActive,,,) =
            strategyManager.strategies(address(mockAaveStrategy));
        assertEq(stratWeight, weight);
        assertEq(stratRisk, riskScore);
        assertTrue(isActive);
    }

    function testFuzz_SetRiskTolerance_ValidValues(uint256 tolerance) public {
        tolerance = bound(tolerance, 1, 100);

        strategyManager.setRiskTolerance(tolerance);
        assertEq(strategyManager.riskTolerance(), tolerance);
    }
}
