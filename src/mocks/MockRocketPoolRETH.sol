// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockRocketPoolRETH
 * @dev Mock implementation of Rocket Pool rETH for testing
 */
contract MockRocketPoolRETH is ERC20 {
    uint256 private _exchangeRate; // rETH to ETH exchange rate (scaled by 1e18)
    
    event TokensMinted(address indexed to, uint256 amount, uint256 ethAmount);
    event TokensBurned(address indexed from, uint256 amount, uint256 ethAmount);
    
    constructor() ERC20("Rocket Pool ETH", "rETH") {
        _exchangeRate = 1.05e18; // Start with 1.05 ETH per rETH (5% premium)
    }

    // Allow contract to receive ETH
    receive() external payable {
        // Mint rETH tokens based on exchange rate
        uint256 rethAmount = (msg.value * 1e18) / _exchangeRate;
        _mint(msg.sender, rethAmount);
    }
    
    /**
     * @dev Get the current ETH value of an amount of rETH
     */
    function getEthValue(uint256 _rethAmount) external view returns (uint256) {
        return (_rethAmount * _exchangeRate) / 1e18;
    }
    
    /**
     * @dev Get the current rETH value of an amount of ETH
     */
    function getRethValue(uint256 _ethAmount) external view returns (uint256) {
        return (_ethAmount * 1e18) / _exchangeRate;
    }
    
    /**
     * @dev Get the current exchange rate (ETH per rETH)
     */
    function getExchangeRate() external view returns (uint256) {
        return _exchangeRate;
    }
    
    /**
     * @dev Mint rETH tokens (simulates depositing ETH)
     */
    function mint(address _to, uint256 _ethAmount) external payable {
        require(_ethAmount > 0, "Invalid ETH amount");
        
        uint256 rethAmount = (_ethAmount * 1e18) / _exchangeRate;
        _mint(_to, rethAmount);
        
        emit TokensMinted(_to, rethAmount, _ethAmount);
    }
    
    /**
     * @dev Burn rETH tokens (simulates withdrawing ETH)
     */
    function burn(uint256 _rethAmount) external {
        require(_rethAmount > 0, "Invalid rETH amount");
        require(balanceOf(msg.sender) >= _rethAmount, "Insufficient balance");
        
        uint256 ethAmount = (_rethAmount * _exchangeRate) / 1e18;
        _burn(msg.sender, _rethAmount);
        
        // In a real implementation, this would transfer ETH
        // For testing, we just emit the event
        emit TokensBurned(msg.sender, _rethAmount, ethAmount);
    }
    
    /**
     * @dev Set exchange rate (for testing purposes)
     */
    function setExchangeRate(uint256 _newRate) external {
        require(_newRate > 0, "Invalid exchange rate");
        _exchangeRate = _newRate;
    }
    
    /**
     * @dev Simulate rewards by increasing exchange rate
     */
    function addRewards(uint256 _rewardBasisPoints) external {
        // Increase exchange rate by reward basis points (10000 = 100%)
        _exchangeRate = (_exchangeRate * (10000 + _rewardBasisPoints)) / 10000;
    }
    
    /**
     * @dev Get total ETH value of all rETH tokens
     */
    function getTotalCollateral() external view returns (uint256) {
        return (totalSupply() * _exchangeRate) / 1e18;
    }
}
