// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AbunfiVault.sol";
import "../src/RiskProfileManager.sol";
import "../src/WithdrawalManager.sol";
import "../src/StrategyManager.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/strategies/LiquidStakingStrategy.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title DeployRiskBasedSystem
 * @dev Deployment script for the complete risk-based fund management system
 */
contract DeployRiskBasedSystem is Script {
    
    // Deployment addresses will be stored here
    address public usdc;
    address public riskProfileManager;
    address public withdrawalManager;
    address public strategyManager;
    address public vault;
    address public aaveStrategy;
    address public compoundStrategy;
    address public liquidStakingStrategy;
    
    // Trusted forwarder for meta-transactions (use zero address for testing)
    address public trustedForwarder = address(0);
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contracts
        _deployTokens();
        _deployRiskManagement();
        _deployStrategies();
        _deployVault();
        _setupRiskAllocations();
        _setupWithdrawalManager();
        
        vm.stopBroadcast();
        
        // Log deployment addresses
        _logDeploymentAddresses();
    }
    
    function _deployTokens() internal {
        console.log("Deploying tokens...");
        
        // Deploy mock USDC for testing (use real USDC address on mainnet)
        usdc = address(new MockERC20("USD Coin", "USDC", 6));
        console.log("USDC deployed at:", usdc);
    }
    
    function _deployRiskManagement() internal {
        console.log("Deploying risk management contracts...");
        
        // Deploy RiskProfileManager
        riskProfileManager = address(new RiskProfileManager());
        console.log("RiskProfileManager deployed at:", riskProfileManager);
        
        // Deploy WithdrawalManager
        withdrawalManager = address(new WithdrawalManager(address(0), usdc)); // Vault address will be set later
        console.log("WithdrawalManager deployed at:", withdrawalManager);
        
        // Deploy StrategyManager
        strategyManager = address(new StrategyManager(riskProfileManager));
        console.log("StrategyManager deployed at:", strategyManager);
    }
    
    function _deployStrategies() internal {
        console.log("Deploying strategies...");
        
        // For testing, we'll use mock addresses for external protocols
        address mockAavePool = address(new MockERC20("Mock Aave Pool", "MAAVE", 18));
        address mockAaveDataProvider = address(new MockERC20("Mock Data Provider", "MDP", 18));
        address mockComet = address(new MockERC20("Mock Comet", "MCOMET", 18));
        address mockCometRewards = address(new MockERC20("Mock Comet Rewards", "MCR", 18));
        address mockStakingToken = address(new MockERC20("Mock Staking Token", "MST", 18));
        
        // Deploy strategies
        aaveStrategy = address(new AaveStrategy(
            usdc,
            mockAavePool,
            mockAaveDataProvider,
            address(0) // Vault address will be set later
        ));
        console.log("AaveStrategy deployed at:", aaveStrategy);
        
        compoundStrategy = address(new CompoundStrategy(
            usdc,
            mockComet,
            mockCometRewards,
            address(0) // Vault address will be set later
        ));
        console.log("CompoundStrategy deployed at:", compoundStrategy);
        
        liquidStakingStrategy = address(new LiquidStakingStrategy(
            usdc,
            mockStakingToken,
            address(0), // Vault address will be set later
            "Liquid Staking Strategy"
        ));
        console.log("LiquidStakingStrategy deployed at:", liquidStakingStrategy);
    }
    
    function _deployVault() internal {
        console.log("Deploying vault...");
        
        // Deploy AbunfiVault
        vault = address(new AbunfiVault(
            usdc,
            trustedForwarder,
            riskProfileManager,
            withdrawalManager
        ));
        console.log("AbunfiVault deployed at:", vault);
        
        // Update vault address in WithdrawalManager
        // Note: This would require adding a setVault function to WithdrawalManager
        console.log("Note: Update vault address in WithdrawalManager manually");
    }
    
    function _setupRiskAllocations() internal {
        console.log("Setting up risk-based allocations...");
        
        // Add strategies to StrategyManager
        StrategyManager sm = StrategyManager(strategyManager);
        
        // Add Aave Strategy (Low risk)
        sm.addStrategy(
            aaveStrategy,
            3000, // 30% weight
            20,   // 20% risk score (low risk)
            5000, // 50% max allocation
            1000  // 10% min allocation
        );
        
        // Add Compound Strategy (Medium risk)
        sm.addStrategy(
            compoundStrategy,
            4000, // 40% weight
            50,   // 50% risk score (medium risk)
            6000, // 60% max allocation
            1500  // 15% min allocation
        );
        
        // Add Liquid Staking Strategy (High risk)
        sm.addStrategy(
            liquidStakingStrategy,
            3000, // 30% weight
            80,   // 80% risk score (high risk)
            4000, // 40% max allocation
            500   // 5% min allocation
        );
        
        // Setup risk level allocations
        
        // LOW RISK: Conservative allocation (70% Aave, 30% Compound)
        address[] memory lowRiskStrategies = new address[](2);
        uint256[] memory lowRiskAllocations = new uint256[](2);
        lowRiskStrategies[0] = aaveStrategy;
        lowRiskStrategies[1] = compoundStrategy;
        lowRiskAllocations[0] = 7000; // 70%
        lowRiskAllocations[1] = 3000; // 30%
        
        sm.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.LOW,
            lowRiskStrategies,
            lowRiskAllocations
        );
        
        // MEDIUM RISK: Balanced allocation (40% Aave, 40% Compound, 20% Liquid Staking)
        address[] memory mediumRiskStrategies = new address[](3);
        uint256[] memory mediumRiskAllocations = new uint256[](3);
        mediumRiskStrategies[0] = aaveStrategy;
        mediumRiskStrategies[1] = compoundStrategy;
        mediumRiskStrategies[2] = liquidStakingStrategy;
        mediumRiskAllocations[0] = 4000; // 40%
        mediumRiskAllocations[1] = 4000; // 40%
        mediumRiskAllocations[2] = 2000; // 20%
        
        sm.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.MEDIUM,
            mediumRiskStrategies,
            mediumRiskAllocations
        );
        
        // HIGH RISK: Aggressive allocation (20% Aave, 30% Compound, 50% Liquid Staking)
        address[] memory highRiskStrategies = new address[](3);
        uint256[] memory highRiskAllocations = new uint256[](3);
        highRiskStrategies[0] = aaveStrategy;
        highRiskStrategies[1] = compoundStrategy;
        highRiskStrategies[2] = liquidStakingStrategy;
        highRiskAllocations[0] = 2000; // 20%
        highRiskAllocations[1] = 3000; // 30%
        highRiskAllocations[2] = 5000; // 50%
        
        sm.setRiskLevelAllocation(
            RiskProfileManager.RiskLevel.HIGH,
            highRiskStrategies,
            highRiskAllocations
        );
        
        console.log("Risk allocations configured successfully");
    }
    
    function _setupWithdrawalManager() internal {
        console.log("Setting up withdrawal manager...");
        
        WithdrawalManager wm = WithdrawalManager(withdrawalManager);
        
        // Set withdrawal window to 7 days
        wm.updateWithdrawalWindow(7 days);
        
        // Set instant withdrawal fee to 1%
        wm.updateInstantWithdrawalFee(100); // 1% in basis points
        
        console.log("Withdrawal manager configured successfully");
    }
    
    function _logDeploymentAddresses() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("USDC:", usdc);
        console.log("RiskProfileManager:", riskProfileManager);
        console.log("WithdrawalManager:", withdrawalManager);
        console.log("StrategyManager:", strategyManager);
        console.log("AbunfiVault:", vault);
        console.log("AaveStrategy:", aaveStrategy);
        console.log("CompoundStrategy:", compoundStrategy);
        console.log("LiquidStakingStrategy:", liquidStakingStrategy);
        console.log("========================\n");
    }
}
