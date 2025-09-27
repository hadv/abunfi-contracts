// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mocks/MockERC20.sol";

contract TestDeploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy a simple test token
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 18);
        testToken.mint(deployer, 1000 * 10 ** 18);

        vm.stopBroadcast();

        console.log("Test token deployed at:", address(testToken));
    }
}
