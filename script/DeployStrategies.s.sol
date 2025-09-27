// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/strategies/LiquidStakingStrategy.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAavePool.sol";
import "../src/mocks/MockAaveDataProvider.sol";
import "../src/mocks/MockComet.sol";
import "../src/mocks/MockCometRewards.sol";

contract DeployStrategies is Script {
    // Strategy configuration
    uint256 public constant AAVE_WEIGHT = 4000; // 40%
    uint256 public constant COMPOUND_WEIGHT = 3500; // 35%
    uint256 public constant LIQUID_STAKING_WEIGHT = 2500; // 25%

    // Core contract addresses (from previous deployment)
    address public constant USDC_ADDRESS = 0x9C34AA00150AAa994F7d53f029c4208c814cdeaA;
    address public constant VAULT_ADDRESS = 0x094eDDFADDd34336853Ca4f738165f39D78532EE;
    address public constant STRATEGY_MANAGER_ADDRESS = 0x939BBFF4BcCCa5A92eCc55Ca8710987bab266848;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ABUNFI STRATEGIES DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        console.log("USDC Address:", USDC_ADDRESS);
        console.log("Vault Address:", VAULT_ADDRESS);
        console.log("StrategyManager Address:", STRATEGY_MANAGER_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock Aave Infrastructure
        console.log("\n1. Deploying Mock Aave Infrastructure...");
        MockAavePool aavePool = new MockAavePool(USDC_ADDRESS);
        MockAaveDataProvider aaveDataProvider = new MockAaveDataProvider();
        MockERC20 aUSDC = new MockERC20("Aave USDC", "aUSDC", 6);

        // Configure Aave mocks
        aavePool.setAToken(USDC_ADDRESS, address(aUSDC));
        aaveDataProvider.setReserveTokens(USDC_ADDRESS, address(aUSDC), address(0), address(0));

        console.log("MockAavePool deployed at:", address(aavePool));
        console.log("MockAaveDataProvider deployed at:", address(aaveDataProvider));
        console.log("aUSDC deployed at:", address(aUSDC));

        // 2. Deploy Mock Compound Infrastructure
        console.log("\n2. Deploying Mock Compound Infrastructure...");
        MockComet comet = new MockComet(USDC_ADDRESS);
        MockCometRewards cometRewards = new MockCometRewards();

        console.log("MockComet deployed at:", address(comet));
        console.log("MockCometRewards deployed at:", address(cometRewards));

        // 3. Deploy AaveStrategy
        console.log("\n3. Deploying AaveStrategy...");
        AaveStrategy aaveStrategy =
            new AaveStrategy(USDC_ADDRESS, address(aavePool), address(aaveDataProvider), VAULT_ADDRESS);
        console.log("AaveStrategy deployed at:", address(aaveStrategy));

        // 4. Deploy CompoundStrategy
        console.log("\n4. Deploying CompoundStrategy...");
        CompoundStrategy compoundStrategy =
            new CompoundStrategy(USDC_ADDRESS, address(comet), address(cometRewards), VAULT_ADDRESS);
        console.log("CompoundStrategy deployed at:", address(compoundStrategy));

        // 5. Deploy LiquidStakingStrategy
        console.log("\n5. Deploying LiquidStakingStrategy...");
        MockERC20 mockStETH = new MockERC20("Liquid Staked ETH", "stETH", 18);
        LiquidStakingStrategy liquidStakingStrategy =
            new LiquidStakingStrategy(USDC_ADDRESS, address(mockStETH), VAULT_ADDRESS, "Liquid Staking Strategy");
        console.log("LiquidStakingStrategy deployed at:", address(liquidStakingStrategy));
        console.log("Mock stETH deployed at:", address(mockStETH));

        vm.stopBroadcast();

        console.log("\n=== STRATEGIES DEPLOYMENT COMPLETE ===");
        console.log("AaveStrategy:", address(aaveStrategy));
        console.log("CompoundStrategy:", address(compoundStrategy));
        console.log("LiquidStakingStrategy:", address(liquidStakingStrategy));
        console.log("\n=== MOCK INFRASTRUCTURE ===");
        console.log("MockAavePool:", address(aavePool));
        console.log("MockAaveDataProvider:", address(aaveDataProvider));
        console.log("aUSDC:", address(aUSDC));
        console.log("MockComet:", address(comet));
        console.log("MockCometRewards:", address(cometRewards));
        console.log("Mock stETH:", address(mockStETH));
    }
}
