// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockCometRewards
 * @dev Mock implementation of Compound V3 CometRewards for testing
 */
contract MockCometRewards {
    mapping(address => mapping(address => uint256)) public rewardOwed;
    
    event RewardClaimed(address indexed comet, address indexed account, uint256 amount);
    
    function claim(address comet, address src, bool shouldAccrue) external {
        uint256 amount = rewardOwed[comet][src];
        if (amount > 0) {
            rewardOwed[comet][src] = 0;
            emit RewardClaimed(comet, src, amount);
        }
    }
    
    function getRewardOwed(address comet, address account) external view returns (uint256) {
        return rewardOwed[comet][account];
    }
    
    // Test helper function
    function setRewardOwed(address comet, address account, uint256 amount) external {
        rewardOwed[comet][account] = amount;
    }
}
