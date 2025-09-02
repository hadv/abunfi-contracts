// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AbunfiVault.sol";
import "../src/StrategyManager.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/strategies/LiquidStakingStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";

/**
 * @title Deploy
 * @dev Main deployment script for Abunfi core contracts
 * Supports deployment to Sepolia testnet and other networks
 */
contract Deploy is Script {
    // Configuration constants
    uint256 public constant INITIAL_USDC_MINT = 10_000_000 * 10**6; // 10M USDC for testing
    uint256 public constant STRATEGY_WEIGHT = 3333; // ~33.33% allocation per strategy
    uint256 public constant AAVE_RISK_SCORE = 20; // Low risk
    uint256 public constant COMPOUND_RISK_SCORE = 25; // Low-medium risk
    uint256 public constant LIQUID_STAKING_RISK_SCORE = 40; // Medium risk
    uint256 public constant MAX_ALLOCATION = 5000; // 50% max allocation
    uint256 public constant MIN_ALLOCATION = 500; // 5% min allocation

    // Sepolia testnet addresses (if using real protocols)
    address public constant SEPOLIA_AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address public constant SEPOLIA_AAVE_DATA_PROVIDER = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ABUNFI CORE DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        console.log("Network:", getNetworkName());

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy USDC token (mock for testnets, real address for mainnet)
        address usdcAddress = _deployUSDC();

        // 2. Deploy core contracts
        AbunfiVault vault = _deployVault(usdcAddress);
        // Create a mock risk profile manager for the strategy manager
        address mockRiskManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        StrategyManager strategyManager = _deployStrategyManager(mockRiskManager);

        // 3. Deploy mock protocol contracts for testing
        (address aavePool, address aaveDataProvider) = _deployMockAave(usdcAddress);
        (address comet, address cometRewards) = _deployMockCompound(usdcAddress);

        // 4. Deploy strategies
        AaveStrategy aaveStrategy = _deployAaveStrategy(usdcAddress, aavePool, aaveDataProvider, address(vault));
        CompoundStrategy compoundStrategy = _deployCompoundStrategy(usdcAddress, comet, cometRewards, address(vault));
        LiquidStakingStrategy liquidStakingStrategy = _deployLiquidStakingStrategy(usdcAddress, address(vault));

        // 5. Configure the system
        _configureSystem(vault, strategyManager, aaveStrategy, compoundStrategy, liquidStakingStrategy);

        vm.stopBroadcast();

        // 6. Save deployment info and display summary
        _saveDeploymentInfo(
            deployer,
            usdcAddress,
            address(vault),
            address(strategyManager),
            address(aaveStrategy),
            address(compoundStrategy),
            address(liquidStakingStrategy)
        );

        _displayDeploymentSummary(
            usdcAddress,
            address(vault),
            address(strategyManager),
            address(aaveStrategy),
            address(compoundStrategy),
            address(liquidStakingStrategy)
        );
    }

    function _deployUSDC() internal returns (address) {
        console.log("\n1. Deploying USDC...");
<<<<<<< HEAD

=======
        
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        if (block.chainid == 1) {
            // Mainnet USDC
            address mainnetUSDC = 0xA0B86a33E6441e6C8c7f1C7C8C7F1C7C8C7F1C7c;
            console.log("Using mainnet USDC at:", mainnetUSDC);
            return mainnetUSDC;
        } else if (block.chainid == 11155111) {
            // Sepolia - deploy mock USDC
            MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
            mockUSDC.mint(msg.sender, INITIAL_USDC_MINT);
            console.log("Mock USDC deployed at:", address(mockUSDC));
<<<<<<< HEAD
            console.log("Minted", INITIAL_USDC_MINT / 10 ** 6, "USDC to deployer");
=======
            console.log("Minted", INITIAL_USDC_MINT / 10**6, "USDC to deployer");
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
            return address(mockUSDC);
        } else {
            // Other networks - deploy mock USDC
            MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
            mockUSDC.mint(msg.sender, INITIAL_USDC_MINT);
            console.log("Mock USDC deployed at:", address(mockUSDC));
            return address(mockUSDC);
        }
    }

    function _deployVault(address usdcAddress) internal returns (AbunfiVault) {
        console.log("\n2. Deploying AbunfiVault...");
        // Deploy risk management contracts first
        address riskProfileManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address withdrawalManager = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        AbunfiVault vault = new AbunfiVault(usdcAddress, address(0), riskProfileManager, withdrawalManager); // No trusted forwarder for now
        console.log("AbunfiVault deployed at:", address(vault));
        return vault;
    }

    function _deployStrategyManager(address riskProfileManagerAddr) internal returns (StrategyManager) {
        console.log("\n3. Deploying StrategyManager...");
        StrategyManager strategyManager = new StrategyManager(riskProfileManagerAddr);
        console.log("StrategyManager deployed at:", address(strategyManager));
        return strategyManager;
    }

    function _deployMockAave(address usdcAddress) internal returns (address, address) {
        console.log("\n4. Deploying Mock Aave contracts...");
<<<<<<< HEAD

=======
        
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        if (block.chainid == 11155111) {
            // For Sepolia, we could use real Aave addresses or mocks
            // Using mocks for simplicity and testing
            MockAaveDataProvider dataProvider = new MockAaveDataProvider();
            MockERC20 aUSDC = new MockERC20("Aave USDC", "aUSDC", 6);
            MockAavePool aavePool = new MockAavePool(usdcAddress);

            // Configure the mock pool
            aavePool.setAToken(usdcAddress, address(aUSDC));
            dataProvider.setReserveTokens(usdcAddress, address(aUSDC), address(0), address(0));

            console.log("Mock Aave Pool deployed at:", address(aavePool));
            console.log("Mock Aave Data Provider deployed at:", address(dataProvider));
            console.log("Mock aUSDC deployed at:", address(aUSDC));

            return (address(aavePool), address(dataProvider));
        } else {
            // For other networks, deploy mocks
            MockAaveDataProvider dataProvider = new MockAaveDataProvider();
            MockERC20 aUSDC = new MockERC20("Aave USDC", "aUSDC", 6);
            MockAavePool aavePool = new MockAavePool(usdcAddress);

            // Configure the mock pool
            aavePool.setAToken(usdcAddress, address(aUSDC));
            dataProvider.setReserveTokens(usdcAddress, address(aUSDC), address(0), address(0));

            console.log("Mock Aave Pool deployed at:", address(aavePool));
            console.log("Mock Aave Data Provider deployed at:", address(dataProvider));
            console.log("Mock aUSDC deployed at:", address(aUSDC));

            return (address(aavePool), address(dataProvider));
        }
    }

    function _deployMockCompound(address usdcAddress) internal returns (address, address) {
        console.log("\n5. Deploying Mock Compound contracts...");
        MockComet comet = new MockComet(usdcAddress);
        MockCometRewards cometRewards = new MockCometRewards();
<<<<<<< HEAD

        console.log("Mock Compound Comet deployed at:", address(comet));
        console.log("Mock Compound Rewards deployed at:", address(cometRewards));

        return (address(comet), address(cometRewards));
    }

    function _deployAaveStrategy(address usdcAddress, address aavePool, address dataProvider, address vault)
        internal
        returns (AaveStrategy)
    {
=======
        
        console.log("Mock Compound Comet deployed at:", address(comet));
        console.log("Mock Compound Rewards deployed at:", address(cometRewards));
        
        return (address(comet), address(cometRewards));
    }

    function _deployAaveStrategy(
        address usdcAddress,
        address aavePool,
        address dataProvider,
        address vault
    ) internal returns (AaveStrategy) {
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        console.log("\n6. Deploying AaveStrategy...");
        AaveStrategy strategy = new AaveStrategy(usdcAddress, aavePool, dataProvider, vault);
        console.log("AaveStrategy deployed at:", address(strategy));
        return strategy;
    }

<<<<<<< HEAD
    function _deployCompoundStrategy(address usdcAddress, address comet, address cometRewards, address vault)
        internal
        returns (CompoundStrategy)
    {
=======
    function _deployCompoundStrategy(
        address usdcAddress,
        address comet,
        address cometRewards,
        address vault
    ) internal returns (CompoundStrategy) {
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        console.log("\n7. Deploying CompoundStrategy...");
        CompoundStrategy strategy = new CompoundStrategy(usdcAddress, comet, cometRewards, vault);
        console.log("CompoundStrategy deployed at:", address(strategy));
        return strategy;
    }

<<<<<<< HEAD
    function _deployLiquidStakingStrategy(address usdcAddress, address vault)
        internal
        returns (LiquidStakingStrategy)
    {
        console.log("\n8. Deploying LiquidStakingStrategy...");

        // Deploy mock staking token for testing
        MockERC20 mockStETH = new MockERC20("Liquid Staked ETH", "stETH", 18);
        LiquidStakingStrategy strategy =
            new LiquidStakingStrategy(usdcAddress, address(mockStETH), vault, "Liquid Staking Strategy");
=======
    function _deployLiquidStakingStrategy(
        address usdcAddress,
        address vault
    ) internal returns (LiquidStakingStrategy) {
        console.log("\n8. Deploying LiquidStakingStrategy...");
        
        // Deploy mock staking token for testing
        MockERC20 mockStETH = new MockERC20("Liquid Staked ETH", "stETH", 18);
        LiquidStakingStrategy strategy = new LiquidStakingStrategy(
            usdcAddress,
            address(mockStETH),
            vault,
            "Liquid Staking Strategy"
        );
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        console.log("LiquidStakingStrategy deployed at:", address(strategy));
        console.log("Mock stETH deployed at:", address(mockStETH));
        return strategy;
    }

    function _configureSystem(
        AbunfiVault vault,
        StrategyManager strategyManager,
        AaveStrategy aaveStrategy,
        CompoundStrategy compoundStrategy,
        LiquidStakingStrategy liquidStakingStrategy
    ) internal {
        console.log("\n9. Configuring system...");

        // Add strategies to vault
        vault.addStrategy(address(aaveStrategy));
        vault.addStrategy(address(compoundStrategy));
        vault.addStrategy(address(liquidStakingStrategy));
        console.log("Added strategies to vault");

        // Add strategies to strategy manager with risk parameters
        strategyManager.addStrategy(
<<<<<<< HEAD
            address(aaveStrategy), STRATEGY_WEIGHT, AAVE_RISK_SCORE, MAX_ALLOCATION, MIN_ALLOCATION
        );

        strategyManager.addStrategy(
            address(compoundStrategy), STRATEGY_WEIGHT, COMPOUND_RISK_SCORE, MAX_ALLOCATION, MIN_ALLOCATION
        );

        strategyManager.addStrategy(
            address(liquidStakingStrategy), STRATEGY_WEIGHT, LIQUID_STAKING_RISK_SCORE, MAX_ALLOCATION, MIN_ALLOCATION
=======
            address(aaveStrategy),
            STRATEGY_WEIGHT,
            AAVE_RISK_SCORE,
            MAX_ALLOCATION,
            MIN_ALLOCATION
        );
        
        strategyManager.addStrategy(
            address(compoundStrategy),
            STRATEGY_WEIGHT,
            COMPOUND_RISK_SCORE,
            MAX_ALLOCATION,
            MIN_ALLOCATION
        );
        
        strategyManager.addStrategy(
            address(liquidStakingStrategy),
            STRATEGY_WEIGHT,
            LIQUID_STAKING_RISK_SCORE,
            MAX_ALLOCATION,
            MIN_ALLOCATION
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        );
        console.log("Added strategies to strategy manager with risk parameters");

        console.log("System configuration complete!");
    }

    function _saveDeploymentInfo(
        address deployer,
        address usdc,
        address vault,
        address strategyManager,
        address aaveStrategy,
        address compoundStrategy,
        address liquidStakingStrategy
    ) internal {
        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
<<<<<<< HEAD
                '  "network": "',
                getNetworkName(),
                '",\n',
                '  "chainId": ',
                vm.toString(block.chainid),
                ",\n",
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "timestamp": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "contracts": {\n',
                '    "usdc": "',
                vm.toString(usdc),
                '",\n',
                '    "vault": "',
                vm.toString(vault),
                '",\n',
                '    "strategyManager": "',
                vm.toString(strategyManager),
                '",\n',
                '    "strategies": {\n',
                '      "aave": "',
                vm.toString(aaveStrategy),
                '",\n',
                '      "compound": "',
                vm.toString(compoundStrategy),
                '",\n',
                '      "liquidStaking": "',
                vm.toString(liquidStakingStrategy),
                '"\n',
                "    }\n",
                "  }\n",
                "}"
            )
        );

        string memory filename = string(abi.encodePacked("deployments/core-", vm.toString(block.chainid), ".json"));
=======
                '  "network": "', getNetworkName(), '",\n',
                '  "chainId": ', vm.toString(block.chainid), ",\n",
                '  "deployer": "', vm.toString(deployer), '",\n',
                '  "timestamp": ', vm.toString(block.timestamp), ",\n",
                '  "contracts": {\n',
                '    "usdc": "', vm.toString(usdc), '",\n',
                '    "vault": "', vm.toString(vault), '",\n',
                '    "strategyManager": "', vm.toString(strategyManager), '",\n',
                '    "strategies": {\n',
                '      "aave": "', vm.toString(aaveStrategy), '",\n',
                '      "compound": "', vm.toString(compoundStrategy), '",\n',
                '      "liquidStaking": "', vm.toString(liquidStakingStrategy), '"\n',
                '    }\n',
                '  }\n',
                '}'
            )
        );

        string memory filename = string(
            abi.encodePacked("deployments/core-", vm.toString(block.chainid), ".json")
        );
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)

        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }

    function _displayDeploymentSummary(
        address usdc,
        address vault,
        address strategyManager,
        address aaveStrategy,
        address compoundStrategy,
        address liquidStakingStrategy
    ) internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("\nCore Contracts:");
        console.log("USDC Token:", usdc);
        console.log("AbunfiVault:", vault);
        console.log("StrategyManager:", strategyManager);
        console.log("\nStrategy Contracts:");
        console.log("AaveStrategy:", aaveStrategy);
        console.log("CompoundStrategy:", compoundStrategy);
        console.log("LiquidStakingStrategy:", liquidStakingStrategy);

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify contracts on Etherscan (if not localhost)");
        console.log("2. Test deposits and withdrawals");
        console.log("3. Monitor strategy performance");
        console.log("4. Set up frontend integration");

        if (block.chainid != 31337) {
            console.log("\n=== VERIFICATION COMMANDS ===");
            console.log("forge verify-contract", vault, "src/AbunfiVault.sol:AbunfiVault --chain-id", block.chainid);
<<<<<<< HEAD
            console.log(
                "forge verify-contract",
                strategyManager,
                "src/StrategyManager.sol:StrategyManager --chain-id",
                block.chainid
            );
            console.log(
                "forge verify-contract",
                aaveStrategy,
                "src/strategies/AaveStrategy.sol:AaveStrategy --chain-id",
                block.chainid
            );
=======
            console.log("forge verify-contract", strategyManager, "src/StrategyManager.sol:StrategyManager --chain-id", block.chainid);
            console.log("forge verify-contract", aaveStrategy, "src/strategies/AaveStrategy.sol:AaveStrategy --chain-id", block.chainid);
>>>>>>> e25290f (feat: Add comprehensive deployment setup for Sepolia testnet)
        }

        console.log("\n=== FRONTEND CONFIG ===");
        console.log("const config = {");
        console.log("  chainId:", block.chainid, ",");
        console.log("  contracts: {");
        console.log("    usdc: '", usdc, "',");
        console.log("    vault: '", vault, "',");
        console.log("    strategyManager: '", strategyManager, "',");
        console.log("    strategies: {");
        console.log("      aave: '", aaveStrategy, "',");
        console.log("      compound: '", compoundStrategy, "',");
        console.log("      liquidStaking: '", liquidStakingStrategy, "'");
        console.log("    }");
        console.log("  }");
        console.log("};");

        console.log("\n=== DEPLOYMENT COMPLETE ===");
    }

    function getNetworkName() internal view returns (string memory) {
        if (block.chainid == 1) return "mainnet";
        if (block.chainid == 11155111) return "sepolia";
        if (block.chainid == 137) return "polygon";
        if (block.chainid == 80001) return "mumbai";
        if (block.chainid == 42161) return "arbitrum";
        if (block.chainid == 421613) return "arbitrum-goerli";
        if (block.chainid == 10) return "optimism";
        if (block.chainid == 420) return "optimism-goerli";
        if (block.chainid == 31337) return "localhost";
        return "unknown";
    }
}
