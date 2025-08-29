// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";

contract BasicSetupTest is Test {
    MockERC20 public mockUSDC;
    AbunfiVault public vault;
    
    address public user1;
    
    function setUp() public {
        user1 = makeAddr("user1");
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        vault = new AbunfiVault(address(mockUSDC));
        mockUSDC.mint(user1, 1000 * 10**6);
    }
    
    function test_MockUSDC_DeploySuccessfully() public {
        assertEq(mockUSDC.name(), "Mock USDC");
        assertEq(mockUSDC.symbol(), "USDC");
        assertEq(mockUSDC.decimals(), 6);
    }
    
    function test_AbunfiVault_DeploySuccessfully() public {
        assertEq(address(vault.asset()), address(mockUSDC));
        assertEq(vault.MINIMUM_DEPOSIT(), 4 * 10**6);
    }
}
