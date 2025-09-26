// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AbunfiVault.sol";
import "../src/StrategyManager.sol";
import "../src/strategies/AaveStrategy.sol";
import "../src/strategies/CompoundStrategy.sol";
import "../src/strategies/LiquidStakingStrategy.sol";
import "../src/mocks/MockERC20.sol";

contract ConfigureSystem is Script {
    // Strategy configuration
    uint256 public constant AAVE_WEIGHT = 4000; // 40%
    uint256 public constant COMPOUND_WEIGHT = 3500; // 35%
    uint256 public constant LIQUID_STAKING_WEIGHT = 2500; // 25%

    // Core contract addresses (from previous deployments)
    address public constant USDC_ADDRESS = 0x9C34AA00150AAa994F7d53f029c4208c814cdeaA;
    address public constant VAULT_ADDRESS = 0x094eDDFADDd34336853Ca4f738165f39D78532EE;
    address public constant STRATEGY_MANAGER_ADDRESS = 0x939BBFF4BcCCa5A92eCc55Ca8710987bab266848;

    // Strategy addresses (from previous deployment)
    address public constant AAVE_STRATEGY_ADDRESS = 0xC29FA5A76E45D59731928CFCAEfDA7715da086f3;
    address public constant COMPOUND_STRATEGY_ADDRESS = 0x050B21B2191eA6dEB0f12fD4fd40C7b59f6E397a;
    address public constant LIQUID_STAKING_STRATEGY_ADDRESS = 0x9492368373a17be8Ed82Ea32a0B3e405782123E7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ABUNFI SYSTEM CONFIGURATION ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        MockERC20 usdc = MockERC20(USDC_ADDRESS);
        AbunfiVault vault = AbunfiVault(VAULT_ADDRESS);
        StrategyManager strategyManager = StrategyManager(STRATEGY_MANAGER_ADDRESS);
        AaveStrategy aaveStrategy = AaveStrategy(AAVE_STRATEGY_ADDRESS);
        CompoundStrategy compoundStrategy = CompoundStrategy(COMPOUND_STRATEGY_ADDRESS);
        LiquidStakingStrategy liquidStakingStrategy = LiquidStakingStrategy(LIQUID_STAKING_STRATEGY_ADDRESS);

        console.log("\n1. Adding strategies to StrategyManager...");

        // Add strategies to StrategyManager with risk parameters
        // addStrategy(address, weight, riskScore, maxAllocation, minAllocation)
        // Risk scores are 0-100, weights are basis points (0-10000)
        strategyManager.addStrategy(AAVE_STRATEGY_ADDRESS, AAVE_WEIGHT, 30, 5000, 1000); // Medium risk (30/100)
        console.log("Added AaveStrategy with weight:", AAVE_WEIGHT);

        strategyManager.addStrategy(COMPOUND_STRATEGY_ADDRESS, COMPOUND_WEIGHT, 25, 4500, 1000); // Lower risk (25/100)
        console.log("Added CompoundStrategy with weight:", COMPOUND_WEIGHT);

        strategyManager.addStrategy(LIQUID_STAKING_STRATEGY_ADDRESS, LIQUID_STAKING_WEIGHT, 40, 3000, 500); // Higher risk (40/100)
        console.log("Added LiquidStakingStrategy with weight:", LIQUID_STAKING_WEIGHT);

        console.log("\n2. Funding deployer with USDC for testing...");
        // Mint some USDC to deployer for testing
        uint256 testAmount = 100_000 * 10 ** 6; // 100K USDC
        usdc.mint(deployer, testAmount);
        console.log("Minted", testAmount / 10 ** 6, "USDC to deployer");

        console.log("\n3. Testing vault deposit...");
        // Approve and deposit to vault
        uint256 depositAmount = 10_000 * 10 ** 6; // 10K USDC
        usdc.approve(VAULT_ADDRESS, depositAmount);
        vault.deposit(depositAmount);
        console.log("Deposited", depositAmount / 10 ** 6, "USDC to vault");

        vm.stopBroadcast();

        console.log("\n=== SYSTEM CONFIGURATION COMPLETE ===");
        console.log("All strategies added to StrategyManager");
        console.log("System funded and tested");
        console.log("Vault deposit successful");

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("USDC Token:", USDC_ADDRESS);
        console.log("AbunfiVault:", VAULT_ADDRESS);
        console.log("StrategyManager:", STRATEGY_MANAGER_ADDRESS);
        console.log("AaveStrategy:", AAVE_STRATEGY_ADDRESS);
        console.log("CompoundStrategy:", COMPOUND_STRATEGY_ADDRESS);
        console.log("LiquidStakingStrategy:", LIQUID_STAKING_STRATEGY_ADDRESS);

        console.log("\nABUNFI SYSTEM FULLY DEPLOYED ON SEPOLIA!");
    }
}
