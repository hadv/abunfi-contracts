// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AbunfiVault.sol";
import "../src/StrategyManager.sol";
import "../src/mocks/MockERC20.sol";

contract DeployCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ABUNFI CORE DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Test USDC
        console.log("\n1. Deploying Test USDC...");
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(deployer, 10_000_000 * 10 ** 6); // 10M USDC
        console.log("Test USDC deployed at:", address(usdc));

        // 2. Deploy AbunfiVault (with minimal parameters for testing)
        console.log("\n2. Deploying AbunfiVault...");
        AbunfiVault vault = new AbunfiVault(
            address(usdc), // asset
            address(0), // trustedForwarder (none for now)
            address(0), // riskProfileManager (none for now)
            address(0) // withdrawalManager (none for now)
        );
        console.log("AbunfiVault deployed at:", address(vault));

        // 3. Deploy StrategyManager
        console.log("\n3. Deploying StrategyManager...");
        StrategyManager strategyManager = new StrategyManager(address(0)); // no risk profile manager for now
        console.log("StrategyManager deployed at:", address(strategyManager));

        vm.stopBroadcast();

        console.log("\n=== CORE DEPLOYMENT COMPLETE ===");
        console.log("USDC:", address(usdc));
        console.log("Vault:", address(vault));
        console.log("StrategyManager:", address(strategyManager));
    }
}
