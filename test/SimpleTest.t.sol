// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockStrategy.sol";

contract SimpleTestTest is Test {
    function test_SimpleTest_DeployMockERC20Successfully() public {
        MockERC20 mockToken = new MockERC20("Test Token", "TEST", 18);

        assertEq(mockToken.name(), "Test Token");
        assertEq(mockToken.symbol(), "TEST");
        assertEq(mockToken.decimals(), 18);
    }

    function test_SimpleTest_DeployAbunfiVaultSuccessfully() public {
        // Deploy mock USDC first
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy vault
        AbunfiVault vault = new AbunfiVault(address(mockUSDC), address(0));

        assertEq(address(vault.asset()), address(mockUSDC));
    }

    function test_SimpleTest_DeployMockStrategySuccessfully() public {
        // Deploy mock USDC first
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "USDC", 6);

        // Deploy mock strategy
        MockStrategy strategy = new MockStrategy(
            address(mockUSDC),
            "Test Strategy",
            500 // 5% APY
        );

        assertEq(strategy.name(), "Test Strategy");
        assertEq(address(strategy.asset()), address(mockUSDC));
        assertEq(strategy.getAPY(), 500);
    }
}
