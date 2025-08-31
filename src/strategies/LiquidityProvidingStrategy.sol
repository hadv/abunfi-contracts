// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAbunfiStrategy.sol";
import "../mocks/MockERC20.sol";

/**
 * @title LiquidityProvidingStrategy
 * @dev Strategy for providing liquidity to AMMs (Curve, Uniswap V3)
 */
contract LiquidityProvidingStrategy is IAbunfiStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    address public immutable pool; // Curve pool or Uniswap V3 pool
    address public immutable vault;
    string public name;

    uint256 public totalDeposited;
    uint256 public lastHarvestTime;
    uint256 public riskTolerance = 50; // Default 50%

    // Pool management
    struct Pool {
        address poolAddress;
        string poolType; // "Curve" or "UniswapV3"
        uint256 apy;
        uint256 riskScore;
        bool isActive;
    }

    mapping(address => Pool) public pools;
    address[] public poolList;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yield);
    event PoolAdded(address indexed pool, string poolType);
    event PoolDeactivated(address indexed pool);
    event PoolUpdated(address indexed pool);
    event PoolRebalanced(address indexed pool, uint256 oldAmount, uint256 newAmount);
    event RewardsHarvested(uint256 amount);
    event LiquidityAdded(address indexed pool, uint256 amount);
    event LiquidityRemoved(address indexed pool, uint256 amount);
    event APYUpdated(address indexed pool, uint256 oldAPY, uint256 newAPY);
    event PoolAPYUpdated(uint256 indexed poolId, uint256 feeAPY, uint256 rewardAPY);

    constructor(address assetAddress, address _pool, address _vault, string memory _name) Ownable(msg.sender) {
        require(assetAddress != address(0), "Invalid asset");
        require(_pool != address(0), "Invalid pool");
        require(_vault != address(0), "Invalid vault");

        _asset = IERC20(assetAddress);
        pool = _pool;
        vault = _vault;
        name = _name;
        lastHarvestTime = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    /**
     * @dev Deposit assets into the strategy
     */
    function deposit(uint256 _amount) external override onlyVault nonReentrant {
        require(_amount > 0, "Amount must be positive");

        // Tokens should already be transferred by vault
        // In a real implementation, this would add liquidity to the pool
        // For testing, we just track the deposit
        totalDeposited += _amount;

        emit Deposited(_amount);
        emit LiquidityAdded(pool, _amount);
    }

    /**
     * @dev Withdraw assets from the strategy
     */
    function withdraw(uint256 _amount) external override onlyVault nonReentrant {
        require(_amount > 0, "Amount must be positive");
        require(_amount <= totalDeposited, "Insufficient balance");

        // For testing, we simulate by minting tokens to this contract first
        if (_asset.balanceOf(address(this)) < _amount) {
            // Mint the required tokens to simulate liquidity removal
            MockERC20(address(_asset)).mint(address(this), _amount);
        }

        totalDeposited -= _amount;
        _asset.safeTransfer(vault, _amount);

        emit Withdrawn(_amount);
        emit LiquidityRemoved(pool, _amount);
    }

    /**
     * @dev Withdraw all assets from the strategy
     */
    function withdrawAll() external override onlyVault nonReentrant {
        uint256 balance = totalDeposited;
        if (balance > 0) {
            // For testing, we simulate by minting tokens to this contract first
            if (_asset.balanceOf(address(this)) < balance) {
                // Mint the required tokens to simulate liquidity removal
                MockERC20(address(_asset)).mint(address(this), balance);
            }

            totalDeposited = 0;
            _asset.safeTransfer(vault, balance);
            emit Withdrawn(balance);
            emit LiquidityRemoved(pool, balance);
        }
    }

    /**
     * @dev Harvest yield from the strategy
     */
    function harvest() external override onlyVault returns (uint256) {
        // Simulate LP rewards (3% annually)
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        uint256 annualRate = 300; // 3% in basis points
        uint256 yield = (totalDeposited * annualRate * timeElapsed) / (365 days * 10000);

        lastHarvestTime = block.timestamp;

        if (yield > 0) {
            // In a real implementation, this would claim LP rewards
            // For testing, we simulate by adding yield
            totalDeposited += yield;
            emit Harvested(yield);
            emit RewardsHarvested(yield);
        }

        return yield;
    }

    /**
     * @dev Get total assets under management
     */
    function totalAssets() external view override returns (uint256) {
        return totalDeposited;
    }

    /**
     * @dev Get current APY
     */
    function getAPY() external pure override returns (uint256) {
        return 300; // 3% APY in basis points
    }

    /**
     * @dev Get asset address
     */
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Get strategy name
     */
    function getName() external view returns (string memory) {
        return name;
    }

    /**
     * @dev Add liquidity to pool
     */
    function addLiquidity(uint256 _amount0, uint256 _amount1) external onlyVault {
        // Simplified liquidity addition
        totalDeposited += (_amount0 + _amount1);
        emit Deposited(_amount0 + _amount1);
    }

    /**
     * @dev Remove liquidity from pool
     */
    function removeLiquidity(uint256 _liquidity) external onlyVault returns (uint256, uint256) {
        require(_liquidity <= totalDeposited, "Insufficient liquidity");

        totalDeposited -= _liquidity;
        uint256 amount0 = _liquidity / 2;
        uint256 amount1 = _liquidity / 2;

        emit Withdrawn(_liquidity);
        return (amount0, amount1);
    }

    /**
     * @dev Get pool reserves
     */
    function getPoolReserves() external view returns (uint256, uint256) {
        return (totalDeposited / 2, totalDeposited / 2);
    }

    /**
     * @dev Calculate optimal liquidity amounts
     */
    function calculateOptimalAmounts(uint256 _amount0Desired, uint256 _amount1Desired)
        external
        view
        returns (uint256, uint256)
    {
        // Simplified calculation - equal amounts
        uint256 optimal = (_amount0Desired + _amount1Desired) / 2;
        return (optimal, optimal);
    }

    /**
     * @dev Get LP token balance
     */
    function getLPTokenBalance() external view returns (uint256) {
        return totalDeposited;
    }

    /**
     * @dev Get pool count
     */
    function poolCount() external view returns (uint256) {
        return poolList.length;
    }

    /**
     * @dev Add a new Curve pool
     */
    function addCurvePool(
        address _pool,
        address _lpToken,
        address[] memory _tokens,
        uint256[] memory _weights,
        uint256 _apy,
        uint256 _riskScore
    ) external onlyOwner {
        require(_pool != address(0), "Invalid pool");
        require(_lpToken != address(0), "Invalid LP token");
        require(!pools[_pool].isActive, "Pool already exists");

        pools[_pool] = Pool({poolAddress: _pool, poolType: "Curve", apy: _apy, riskScore: _riskScore, isActive: true});
        poolList.push(_pool);

        emit PoolAdded(_pool, "Curve");
    }

    /**
     * @dev Add a new Uniswap V3 pool
     */
    function addUniswapV3Pool(
        address _pool,
        address[] memory _tokens,
        uint256[] memory _weights,
        uint256 _apy,
        uint256 _riskScore
    ) external onlyOwner {
        require(_pool != address(0), "Invalid pool");
        require(!pools[_pool].isActive, "Pool already exists");

        pools[_pool] =
            Pool({poolAddress: _pool, poolType: "UniswapV3", apy: _apy, riskScore: _riskScore, isActive: true});
        poolList.push(_pool);

        emit PoolAdded(_pool, "UniswapV3");
    }

    /**
     * @dev Deactivate a pool
     */
    function deactivatePool(address _pool) external onlyOwner {
        require(pools[_pool].isActive, "Pool not active");
        pools[_pool].isActive = false;
        emit PoolDeactivated(_pool);
    }

    /**
     * @dev Update pool APY
     */
    function updatePoolAPY(uint256 _poolId, uint256 _newAPY) external onlyOwner {
        require(_poolId < poolList.length, "Invalid pool ID");
        address poolAddress = poolList[_poolId];
        require(pools[poolAddress].isActive, "Pool not active");

        pools[poolAddress].apy = _newAPY;
        emit PoolUpdated(poolAddress);
    }

    /**
     * @dev Set risk tolerance
     */
    function setRiskTolerance(uint256 _riskTolerance) external onlyOwner {
        require(_riskTolerance <= 100, "Risk tolerance must be <= 100");
        riskTolerance = _riskTolerance;
    }

    /**
     * @dev Get max single pool allocation
     */
    function maxSinglePoolAllocation() external pure returns (uint256) {
        return 5000; // 50% in basis points
    }

    /**
     * @dev Calculate impermanent loss for a pool
     */
    function calculateImpermanentLoss(uint256 _poolId) external pure returns (uint256) {
        // Simplified IL calculation
        return 100; // 1% IL
    }

    /**
     * @dev Get price deviation for a pool
     */
    function getPriceDeviation(uint256 _poolId) external pure returns (uint256) {
        // Simplified price deviation
        return 50; // 0.5% deviation
    }

    /**
     * @dev Rebalance pools
     */
    function rebalance() external onlyOwner {
        // Simple rebalancing logic
        emit PoolRebalanced(address(0), 0, 0);
    }

    /**
     * @dev Get pool allocation
     */
    function getPoolAllocation(uint256 _poolId) external view returns (uint256) {
        if (_poolId >= poolList.length) return 0;
        address poolAddress = poolList[_poolId];
        if (!pools[poolAddress].isActive) return 0;

        // Simple allocation based on total deposited
        return totalDeposited;
    }

    /**
     * @dev Get total fees earned
     */
    function getTotalFeesEarned() external view returns (uint256) {
        // Simplified fee calculation
        return totalDeposited / 100; // 1% of total deposited as fees
    }

    /**
     * @dev Emergency withdraw function
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
