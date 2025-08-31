// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockLidoStETH
 * @dev Mock implementation of Lido stETH for testing
 */
contract MockLidoStETH is ERC20 {
    uint256 private _totalPooledEther;
    uint256 private _totalShares;

    mapping(address => uint256) private _shares;

    event Submitted(address indexed sender, uint256 amount, address referral);

    constructor() ERC20("Liquid staked Ether 2.0", "stETH") {
        _totalPooledEther = 1000000 ether; // 1M ETH
        _totalShares = 1000000 ether; // 1:1 ratio initially
    }

    // Allow contract to receive ETH
    receive() external payable {
        // Mint stETH tokens equal to ETH received
        _mint(msg.sender, msg.value);
    }

    /**
     * @dev Submit ETH to the pool and mint stETH
     */
    function submit(address _referral) external payable returns (uint256) {
        require(msg.value > 0, "ZERO_DEPOSIT");

        uint256 sharesAmount = getSharesByPooledEth(msg.value);
        _shares[msg.sender] += sharesAmount;
        _totalShares += sharesAmount;
        _totalPooledEther += msg.value;

        uint256 tokensAmount = msg.value; // 1:1 for simplicity
        _mint(msg.sender, tokensAmount);

        emit Submitted(msg.sender, msg.value, _referral);
        return tokensAmount;
    }

    /**
     * @dev Get shares amount by pooled ETH amount
     */
    function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
        if (_totalPooledEther == 0) {
            return _ethAmount;
        }
        return (_ethAmount * _totalShares) / _totalPooledEther;
    }

    /**
     * @dev Get pooled ETH amount by shares
     */
    function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
        if (_totalShares == 0) {
            return 0;
        }
        return (_sharesAmount * _totalPooledEther) / _totalShares;
    }

    /**
     * @dev Get shares of account
     */
    function sharesOf(address _account) external view returns (uint256) {
        return _shares[_account];
    }

    /**
     * @dev Get total pooled ether
     */
    function getTotalPooledEther() external view returns (uint256) {
        return _totalPooledEther;
    }

    /**
     * @dev Get total shares
     */
    function getTotalShares() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Mock function to simulate staking rewards
     */
    function addRewards(uint256 _rewardAmount) external {
        _totalPooledEther += _rewardAmount;
        // This increases the value of existing shares
    }

    /**
     * @dev Accrue rewards for testing
     */
    function accrueRewards() external {
        // Simulate 1% rewards
        uint256 rewardAmount = _totalPooledEther / 100;
        _totalPooledEther += rewardAmount;
    }

    /**
     * @dev Override transfer to handle shares properly
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 sharesToTransfer = getSharesByPooledEth(amount);
        _shares[msg.sender] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to handle shares properly
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 sharesToTransfer = getSharesByPooledEth(amount);
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        return super.transferFrom(from, to, amount);
    }
}
