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
 * @title DeploySepolia
 * @dev Deployment script specifically for Sepolia testnet
 * Includes proper configuration for testing production-like scenarios
 */
contract DeploySepolia is Script {
    // Sepolia configuration
    uint256 public constant INITIAL_USDC_MINT = 10_000_000 * 10 ** 6; // 10M USDC for testing
    uint256 public constant DEPLOYER_USDC_AMOUNT = 1_000_000 * 10 ** 6; // 1M USDC for deployer
    uint256 public constant TEST_USER_USDC_AMOUNT = 10_000 * 10 ** 6; // 10K USDC per test user

    // Strategy configuration
    uint256 public constant AAVE_WEIGHT = 4000; // 40%
    uint256 public constant COMPOUND_WEIGHT = 3500; // 35%
    uint256 public constant LIQUID_STAKING_WEIGHT = 2500; // 25%

    // Risk parameters
    uint256 public constant AAVE_RISK_SCORE = 15; // Very low risk
    uint256 public constant COMPOUND_RISK_SCORE = 20; // Low risk
    uint256 public constant LIQUID_STAKING_RISK_SCORE = 35; // Medium risk

    uint256 public constant MAX_ALLOCATION = 6000; // 60% max allocation
    uint256 public constant MIN_ALLOCATION = 1000; // 10% min allocation

    // Test user addresses for funding
    address[] internal testUsers = [
        0x1234567890123456789012345678901234567890,
        0x2345678901234567890123456789012345678901,
        0x3456789012345678901234567890123456789012
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        require(block.chainid == 11155111, "This script is only for Sepolia testnet");

        console.log("=== ABUNFI SEPOLIA TESTNET DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        require(deployer.balance >= 0.1 ether, "Insufficient ETH balance for deployment");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy USDC token for testing
        MockERC20 usdc = _deployTestUSDC(deployer);

        // 2. Deploy core contracts
        AbunfiVault vault = _deployVault(address(usdc));
        // Create a mock risk profile manager for the strategy manager
        address mockRiskManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        StrategyManager strategyManager = _deployStrategyManager(mockRiskManager);

        // 3. Deploy mock protocol contracts
        (MockAavePool aavePool, MockAaveDataProvider aaveDataProvider, MockERC20 aUSDC) = _deployMockAave(address(usdc));
        (MockComet comet, MockCometRewards cometRewards) = _deployMockCompound(address(usdc));

        // 4. Deploy strategies
        AaveStrategy aaveStrategy =
            _deployAaveStrategy(address(usdc), address(aavePool), address(aaveDataProvider), address(vault));
        CompoundStrategy compoundStrategy =
            _deployCompoundStrategy(address(usdc), address(comet), address(cometRewards), address(vault));
        LiquidStakingStrategy liquidStakingStrategy = _deployLiquidStakingStrategy(address(usdc), address(vault));

        // 5. Configure the system
        _configureSystem(vault, strategyManager, aaveStrategy, compoundStrategy, liquidStakingStrategy);

        // 6. Fund test accounts
        _fundTestAccounts(usdc);

        // 7. Initialize strategies with some funds for testing
        _initializeStrategies(usdc, vault, aaveStrategy, compoundStrategy, liquidStakingStrategy);

        vm.stopBroadcast();

        // 8. Save deployment info and display summary
        _saveSepoliaDeploymentInfo(
            deployer,
            address(usdc),
            address(vault),
            address(strategyManager),
            address(aaveStrategy),
            address(compoundStrategy),
            address(liquidStakingStrategy),
            address(aavePool),
            address(comet)
        );

        _displaySepoliaDeploymentSummary(
            address(usdc),
            address(vault),
            address(strategyManager),
            address(aaveStrategy),
            address(compoundStrategy),
            address(liquidStakingStrategy)
        );
    }

    function _deployTestUSDC(address deployer) internal returns (MockERC20) {
        console.log("\n1. Deploying Test USDC...");
        MockERC20 usdc = new MockERC20("USD Coin (Test)", "USDC", 6);

        // Mint initial supply
        usdc.mint(deployer, INITIAL_USDC_MINT);

        console.log("Test USDC deployed at:", address(usdc));
        console.log("Minted", INITIAL_USDC_MINT / 10 ** 6, "USDC to deployer");

        return usdc;
    }

    function _deployVault(address usdcAddress) internal returns (AbunfiVault) {
        console.log("\n2. Deploying AbunfiVault...");
        // Deploy risk management contracts first
        address riskProfileManagerAddr = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address withdrawalManagerAddr = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        AbunfiVault vault = new AbunfiVault(usdcAddress, address(0), riskProfileManagerAddr, withdrawalManagerAddr);
        console.log("AbunfiVault deployed at:", address(vault));
        return vault;
    }

    function _deployStrategyManager(address riskProfileManagerAddr) internal returns (StrategyManager) {
        console.log("\n3. Deploying StrategyManager...");
        StrategyManager strategyManager = new StrategyManager(riskProfileManagerAddr);
        console.log("StrategyManager deployed at:", address(strategyManager));
        return strategyManager;
    }

    function _deployMockAave(address usdcAddress) internal returns (MockAavePool, MockAaveDataProvider, MockERC20) {
        console.log("\n4. Deploying Mock Aave V3 contracts...");

        MockAaveDataProvider dataProvider = new MockAaveDataProvider();
        MockERC20 aUSDC = new MockERC20("Aave USDC", "aUSDC", 6);
        MockAavePool aavePool = new MockAavePool(usdcAddress);

        // Configure the mock pool
        aavePool.setAToken(usdcAddress, address(aUSDC));
        dataProvider.setReserveTokens(usdcAddress, address(aUSDC), address(0), address(0));

        console.log("Mock Aave Pool deployed at:", address(aavePool));
        console.log("Mock Aave Data Provider deployed at:", address(dataProvider));
        console.log("Mock aUSDC deployed at:", address(aUSDC));

        return (aavePool, dataProvider, aUSDC);
    }

    function _deployMockCompound(address usdcAddress) internal returns (MockComet, MockCometRewards) {
        console.log("\n5. Deploying Mock Compound V3 contracts...");
        MockComet comet = new MockComet(usdcAddress);
        MockCometRewards cometRewards = new MockCometRewards();

        console.log("Mock Compound Comet deployed at:", address(comet));
        console.log("Mock Compound Rewards deployed at:", address(cometRewards));

        return (comet, cometRewards);
    }

    function _deployAaveStrategy(address usdcAddress, address aavePool, address dataProvider, address vault)
        internal
        returns (AaveStrategy)
    {
        console.log("\n6. Deploying AaveStrategy...");
        AaveStrategy strategy = new AaveStrategy(usdcAddress, aavePool, dataProvider, vault);
        console.log("AaveStrategy deployed at:", address(strategy));
        return strategy;
    }

    function _deployCompoundStrategy(address usdcAddress, address comet, address cometRewards, address vault)
        internal
        returns (CompoundStrategy)
    {
        console.log("\n7. Deploying CompoundStrategy...");
        CompoundStrategy strategy = new CompoundStrategy(usdcAddress, comet, cometRewards, vault);
        console.log("CompoundStrategy deployed at:", address(strategy));
        return strategy;
    }

    function _deployLiquidStakingStrategy(address usdcAddress, address vault) internal returns (LiquidStakingStrategy) {
        console.log("\n8. Deploying LiquidStakingStrategy...");

        MockERC20 mockStETH = new MockERC20("Liquid Staked ETH", "stETH", 18);
        LiquidStakingStrategy strategy =
            new LiquidStakingStrategy(usdcAddress, address(mockStETH), vault, "Liquid Staking Strategy");
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

        // Add strategies to vault with specific weights
        vault.addStrategyWithWeight(address(aaveStrategy), AAVE_WEIGHT);
        vault.addStrategyWithWeight(address(compoundStrategy), COMPOUND_WEIGHT);
        vault.addStrategyWithWeight(address(liquidStakingStrategy), LIQUID_STAKING_WEIGHT);

        console.log("Added strategies to vault with weights");

        // Add strategies to strategy manager
        strategyManager.addStrategy(address(aaveStrategy), AAVE_WEIGHT, AAVE_RISK_SCORE, MAX_ALLOCATION, MIN_ALLOCATION);

        strategyManager.addStrategy(
            address(compoundStrategy), COMPOUND_WEIGHT, COMPOUND_RISK_SCORE, MAX_ALLOCATION, MIN_ALLOCATION
        );

        strategyManager.addStrategy(
            address(liquidStakingStrategy),
            LIQUID_STAKING_WEIGHT,
            LIQUID_STAKING_RISK_SCORE,
            MAX_ALLOCATION,
            MIN_ALLOCATION
        );

        console.log("Added strategies to strategy manager");
        console.log("System configuration complete!");
    }

    function _fundTestAccounts(MockERC20 usdc) internal {
        console.log("\n10. Funding test accounts...");

        for (uint256 i = 0; i < testUsers.length; i++) {
            usdc.mint(testUsers[i], TEST_USER_USDC_AMOUNT);
            console.log("Funded test user with USDC:", testUsers[i]);
        }
    }

    function _initializeStrategies(
        MockERC20 usdc,
        AbunfiVault vault,
        AaveStrategy aaveStrategy,
        CompoundStrategy compoundStrategy,
        LiquidStakingStrategy liquidStakingStrategy
    ) internal {
        console.log("\n11. Initializing strategies with test funds...");

        uint256 initAmount = 50_000 * 10 ** 6; // 50K USDC

        // Approve vault to spend USDC
        usdc.approve(address(vault), initAmount);

        // Make initial deposit to test the system
        vault.deposit(initAmount);

        console.log("Made initial deposit of", initAmount / 10 ** 6, "USDC to vault");
        console.log("Vault total deposits:", vault.totalDeposits() / 10 ** 6, "USDC");
    }

    function _saveSepoliaDeploymentInfo(
        address deployer,
        address usdc,
        address vault,
        address strategyManager,
        address aaveStrategy,
        address compoundStrategy,
        address liquidStakingStrategy,
        address aavePool,
        address comet
    ) internal {
        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
                '  "network": "sepolia",\n',
                '  "chainId": 11155111,\n',
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "timestamp": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "blockNumber": ',
                vm.toString(block.number),
                ",\n",
                '  "contracts": {\n',
                '    "core": {\n',
                '      "usdc": "',
                vm.toString(usdc),
                '",\n',
                '      "vault": "',
                vm.toString(vault),
                '",\n',
                '      "strategyManager": "',
                vm.toString(strategyManager),
                '"\n',
                "    },\n",
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
                "    },\n",
                '    "mocks": {\n',
                '      "aavePool": "',
                vm.toString(aavePool),
                '",\n',
                '      "compoundComet": "',
                vm.toString(comet),
                '"\n',
                "    }\n",
                "  },\n",
                '  "configuration": {\n',
                '    "strategyWeights": {\n',
                '      "aave": ',
                vm.toString(AAVE_WEIGHT),
                ",\n",
                '      "compound": ',
                vm.toString(COMPOUND_WEIGHT),
                ",\n",
                '      "liquidStaking": ',
                vm.toString(LIQUID_STAKING_WEIGHT),
                "\n",
                "    },\n",
                '    "riskScores": {\n',
                '      "aave": ',
                vm.toString(AAVE_RISK_SCORE),
                ",\n",
                '      "compound": ',
                vm.toString(COMPOUND_RISK_SCORE),
                ",\n",
                '      "liquidStaking": ',
                vm.toString(LIQUID_STAKING_RISK_SCORE),
                "\n",
                "    }\n",
                "  },\n",
                '  "testUsers": [\n'
            )
        );

        // Add test users
        for (uint256 i = 0; i < testUsers.length; i++) {
            deploymentInfo = string(
                abi.encodePacked(
                    deploymentInfo, '    "', vm.toString(testUsers[i]), '"', i < testUsers.length - 1 ? ",\n" : "\n"
                )
            );
        }

        deploymentInfo = string(abi.encodePacked(deploymentInfo, "  ]\n}"));

        string memory filename = "deployments/sepolia-core.json";
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }

    function _displaySepoliaDeploymentSummary(
        address usdc,
        address vault,
        address strategyManager,
        address aaveStrategy,
        address compoundStrategy,
        address liquidStakingStrategy
    ) internal view {
        console.log("\n=== SEPOLIA DEPLOYMENT SUMMARY ===");
        console.log("Network: Sepolia Testnet");
        console.log("Chain ID: 11155111");
        console.log("Block Number:", block.number);

        console.log("\n=== Core Contracts ===");
        console.log("USDC Token:", usdc);
        console.log("AbunfiVault:", vault);
        console.log("StrategyManager:", strategyManager);

        console.log("\n=== Strategy Contracts ===");
        console.log("AaveStrategy:", aaveStrategy);
        console.log("AaveStrategy Weight:", AAVE_WEIGHT);
        console.log("CompoundStrategy:", compoundStrategy);
        console.log("CompoundStrategy Weight:", COMPOUND_WEIGHT);
        console.log("LiquidStakingStrategy:", liquidStakingStrategy);
        console.log("LiquidStakingStrategy Weight:", LIQUID_STAKING_WEIGHT);

        console.log("\n=== Test Users (funded with", TEST_USER_USDC_AMOUNT / 10 ** 6, "USDC each) ===");
        for (uint256 i = 0; i < testUsers.length; i++) {
            console.log("Test User", i + 1, ":", testUsers[i]);
        }

        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on Sepolia Etherscan");
        console.log("2. Test user deposits and withdrawals");
        console.log("3. Monitor strategy performance");
        console.log("4. Test gasless transactions (if EIP-7702 enabled)");
        console.log("5. Frontend integration testing");

        console.log("\n=== Verification Commands ===");
        console.log(
            "forge verify-contract",
            vault,
            "src/AbunfiVault.sol:AbunfiVault --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY"
        );
        console.log(
            "forge verify-contract",
            strategyManager,
            "src/StrategyManager.sol:StrategyManager --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY"
        );

        console.log("\n=== Frontend Configuration ===");
        console.log("const SEPOLIA_CONFIG = {");
        console.log("  chainId: 11155111,");
        console.log("  rpcUrl: 'https://sepolia.infura.io/v3/YOUR_PROJECT_ID',");
        console.log("  contracts: {");
        console.log("    usdc: '", usdc, "',");
        console.log("    vault: '", vault, "',");
        console.log("    strategyManager: '", strategyManager, "',");
        console.log("    strategies: {");
        console.log("      aave: '", aaveStrategy, "',");
        console.log("      compound: '", compoundStrategy, "',");
        console.log("      liquidStaking: '", liquidStakingStrategy, "'");
        console.log("    }");
        console.log("  },");
        console.log("  testUsers: [");
        for (uint256 i = 0; i < testUsers.length; i++) {
            console.log("    '", testUsers[i], "'", i < testUsers.length - 1 ? "," : "");
        }
        console.log("  ]");
        console.log("};");

        console.log("\n=== SEPOLIA DEPLOYMENT COMPLETE ===");
        console.log("Ready for production testing on Sepolia testnet!");
    }
}
