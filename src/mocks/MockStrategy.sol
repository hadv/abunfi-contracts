// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IAbunfiStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockStrategy
 * @dev Mock strategy contract for testing purposes
 */
contract MockStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable _asset;
    string private _name;
    uint256 private _apy;
    uint256 public totalDeposited;
    uint256 public totalYield;
    
    // Mock configuration
    uint256 public yieldRate = 100; // Yield per block
    uint256 public lastYieldBlock;
    bool public shouldFailDeposit = false;
    bool public shouldFailWithdraw = false;
    bool public shouldFailHarvest = false;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);
    event YieldRateUpdated(uint256 newRate);

    constructor(
        address assetAddress,
        string memory name_,
        uint256 apy_
    ) Ownable(msg.sender) {
        _asset = IERC20(assetAddress);
        _name = name_;
        _apy = apy_;
        lastYieldBlock = block.number;
    }

    /**
     * @dev Get the underlying asset address
     */
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Deposit assets into the strategy
     */
    function deposit(uint256 amount) external override nonReentrant {
        require(!shouldFailDeposit, "Mock: Deposit failed");
        require(amount > 0, "Cannot deposit 0");
        
        SafeERC20.safeTransferFrom(_asset, msg.sender, address(this), amount);
        totalDeposited += amount;
        
        emit Deposited(amount);
    }

    /**
     * @dev Withdraw specific amount from strategy
     */
    function withdraw(uint256 amount) external override nonReentrant {
        require(!shouldFailWithdraw, "Mock: Withdraw failed");
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= totalAssets(), "Insufficient balance");
        
        if (amount > totalDeposited) {
            totalDeposited = 0;
        } else {
            totalDeposited -= amount;
        }
        
        SafeERC20.safeTransfer(_asset, msg.sender, amount);
        
        emit Withdrawn(amount);
    }

    /**
     * @dev Withdraw all assets from strategy
     */
    function withdrawAll() external override nonReentrant {
        require(!shouldFailWithdraw, "Mock: Withdraw failed");
        
        uint256 balance = totalAssets();
        if (balance > 0) {
            totalDeposited = 0;
            SafeERC20.safeTransfer(_asset, msg.sender, balance);
            emit Withdrawn(balance);
        }
    }

    /**
     * @dev Harvest yield and compound
     */
    function harvest() external override nonReentrant returns (uint256 yield) {
        require(!shouldFailHarvest, "Mock: Harvest failed");
        
        yield = _calculateYield();
        if (yield > 0) {
            totalYield += yield;
            totalDeposited += yield; // Compound the yield
            emit Harvested(yield);
        }
        
        lastYieldBlock = block.number;
        return yield;
    }

    /**
     * @dev Get total assets managed by strategy
     */
    function totalAssets() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /**
     * @dev Get strategy name
     */
    function name() external view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Get current APY
     */
    function getAPY() external view override returns (uint256) {
        return _apy;
    }

    /**
     * @dev Calculate pending yield
     */
    function _calculateYield() internal view returns (uint256) {
        if (totalDeposited == 0) return 0;
        
        uint256 blocksPassed = block.number - lastYieldBlock;
        return (totalDeposited * yieldRate * blocksPassed) / 1000000; // Simplified yield calculation
    }

    /**
     * @dev Get pending yield without harvesting
     */
    function getPendingYield() external view returns (uint256) {
        return _calculateYield();
    }

    // Mock configuration functions for testing

    /**
     * @dev Set APY for testing
     */
    function setAPY(uint256 newAPY) external onlyOwner {
        _apy = newAPY;
    }

    /**
     * @dev Set yield rate for testing
     */
    function setYieldRate(uint256 newRate) external onlyOwner {
        yieldRate = newRate;
        emit YieldRateUpdated(newRate);
    }

    /**
     * @dev Set deposit failure flag for testing
     */
    function setShouldFailDeposit(bool shouldFail) external onlyOwner {
        shouldFailDeposit = shouldFail;
    }

    /**
     * @dev Set withdraw failure flag for testing
     */
    function setShouldFailWithdraw(bool shouldFail) external onlyOwner {
        shouldFailWithdraw = shouldFail;
    }

    /**
     * @dev Set harvest failure flag for testing
     */
    function setShouldFailHarvest(bool shouldFail) external onlyOwner {
        shouldFailHarvest = shouldFail;
    }

    /**
     * @dev Manually add yield for testing
     */
    function addYield(uint256 amount) external onlyOwner {
        totalYield += amount;
        totalDeposited += amount;
    }

    /**
     * @dev Simulate loss for testing
     */
    function simulateLoss(uint256 amount) external onlyOwner {
        require(amount <= totalDeposited, "Loss exceeds deposits");
        totalDeposited -= amount;
    }

    /**
     * @dev Get total yield earned
     */
    function getTotalYield() external view returns (uint256) {
        return totalYield;
    }

    /**
     * @dev Emergency withdraw for owner
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(IERC20(token), owner(), amount);
    }

    /**
     * @dev Mint tokens to this contract for testing
     */
    function mintTokens(uint256 amount) external onlyOwner {
        // This would only work with MockERC20 that has a mint function
        // In real testing, tokens would be transferred from test accounts
        totalDeposited += amount;
    }

    /**
     * @dev Set name for testing
     */
    function setName(string memory newName) external onlyOwner {
        _name = newName;
    }

    /**
     * @dev Get strategy statistics
     */
    function getStats() external view returns (
        uint256 deposited,
        uint256 yield,
        uint256 apy,
        uint256 pendingYield
    ) {
        return (
            totalDeposited,
            totalYield,
            _apy,
            _calculateYield()
        );
    }

    /**
     * @dev Simulate time passage for yield calculation
     */
    function simulateTimePassage(uint256 blocks) external onlyOwner {
        lastYieldBlock = block.number - blocks;
    }

    /**
     * @dev Reset strategy state for testing
     */
    function reset() external onlyOwner {
        totalDeposited = 0;
        totalYield = 0;
        lastYieldBlock = block.number;
        shouldFailDeposit = false;
        shouldFailWithdraw = false;
        shouldFailHarvest = false;
    }
}
