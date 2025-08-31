// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockComet
 * @dev Mock implementation of Compound V3 Comet for testing
 */
contract MockComet {
    IERC20 public baseToken;
    mapping(address => uint256) public balances;
    uint256 public utilization = 8000; // 80%
    uint64 public supplyRate = 158247046; // ~5% APY in per-second rate

    event Supply(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor(address _baseToken) {
        baseToken = IERC20(_baseToken);
    }

    function supply(address asset, uint256 amount) external {
        require(asset == address(baseToken), "Invalid asset");
        baseToken.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Supply(msg.sender, amount);
    }

    function withdraw(address asset, uint256 amount) external {
        require(asset == address(baseToken), "Invalid asset");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        baseToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function getSupplyRate(uint256 utilization_) external view returns (uint64) {
        return supplyRate;
    }

    function getUtilization() external view returns (uint256) {
        return utilization;
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function accrueAccount(address account) external {
        // Mock implementation - in real Compound this updates interest
    }

    // Test helper functions
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }

    function setUtilization(uint256 _utilization) external {
        utilization = _utilization;
    }

    function setSupplyRate(uint64 _supplyRate) external {
        supplyRate = _supplyRate;
    }
}
