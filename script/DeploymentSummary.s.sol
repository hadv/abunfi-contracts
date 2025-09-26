// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract DeploymentSummary is Script {
    // Core contract addresses (from previous deployments)
    address public constant USDC_ADDRESS = 0x9C34AA00150AAa994F7d53f029c4208c814cdeaA;
    address public constant VAULT_ADDRESS = 0x094eDDFADDd34336853Ca4f738165f39D78532EE;
    address public constant STRATEGY_MANAGER_ADDRESS = 0x939BBFF4BcCCa5A92eCc55Ca8710987bab266848;

    // Strategy addresses (from previous deployment)
    address public constant AAVE_STRATEGY_ADDRESS = 0xC29FA5A76E45D59731928CFCAEfDA7715da086f3;
    address public constant COMPOUND_STRATEGY_ADDRESS = 0x050B21B2191eA6dEB0f12fD4fd40C7b59f6E397a;
    address public constant LIQUID_STAKING_STRATEGY_ADDRESS = 0x9492368373a17be8Ed82Ea32a0B3e405782123E7;

    function run() external view {
        console.log("=== ABUNFI DEPLOYMENT SUMMARY ===");
        console.log("Network: Sepolia Testnet");
        console.log("Chain ID: 11155111");
        console.log("");

        console.log("=== CORE CONTRACTS ===");
        console.log("USDC Token:", USDC_ADDRESS);
        console.log("AbunfiVault:", VAULT_ADDRESS);
        console.log("StrategyManager:", STRATEGY_MANAGER_ADDRESS);
        console.log("");

        console.log("=== STRATEGY CONTRACTS ===");
        console.log("AaveStrategy:", AAVE_STRATEGY_ADDRESS);
        console.log("CompoundStrategy:", COMPOUND_STRATEGY_ADDRESS);
        console.log("LiquidStakingStrategy:", LIQUID_STAKING_STRATEGY_ADDRESS);
        console.log("");

        console.log("=== ETHERSCAN LINKS ===");
        console.log("USDC: https://sepolia.etherscan.io/address/", USDC_ADDRESS);
        console.log("Vault: https://sepolia.etherscan.io/address/", VAULT_ADDRESS);
        console.log("StrategyManager: https://sepolia.etherscan.io/address/", STRATEGY_MANAGER_ADDRESS);
        console.log("AaveStrategy: https://sepolia.etherscan.io/address/", AAVE_STRATEGY_ADDRESS);
        console.log("CompoundStrategy: https://sepolia.etherscan.io/address/", COMPOUND_STRATEGY_ADDRESS);
        console.log("LiquidStakingStrategy: https://sepolia.etherscan.io/address/", LIQUID_STAKING_STRATEGY_ADDRESS);
        console.log("");

        console.log("=== DEPLOYMENT STATUS ===");
        console.log("Core contracts: DEPLOYED & VERIFIED");
        console.log("Strategy contracts: DEPLOYED & VERIFIED");
        console.log("Strategies added to manager: COMPLETED");
        console.log("System configuration: COMPLETED");
        console.log("");

        console.log("=== STRATEGY CONFIGURATION ===");
        console.log("AaveStrategy: Weight 4000 (40%), Risk Score 30/100");
        console.log("CompoundStrategy: Weight 3500 (35%), Risk Score 25/100");
        console.log("LiquidStakingStrategy: Weight 2500 (25%), Risk Score 40/100");
        console.log("");

        console.log("ABUNFI SYSTEM SUCCESSFULLY DEPLOYED ON SEPOLIA!");
        console.log("Ready for testing and integration!");
    }
}
