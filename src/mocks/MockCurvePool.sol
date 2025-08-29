// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockCurvePool
 * @dev Mock implementation of Curve Finance pool for testing
 */
contract MockCurvePool is ERC20 {
    IERC20[] public coins;
    uint256[] public balances;
    uint256 private _fee; // Fee in basis points (10000 = 100%)
    uint256 private _adminFee; // Admin fee in basis points
    
    event AddLiquidity(address indexed provider, uint256[] amounts, uint256 lpTokens);
    event RemoveLiquidity(address indexed provider, uint256 lpTokens, uint256[] amounts);
    event Exchange(address indexed buyer, int128 sold_id, uint256 tokens_sold, int128 bought_id, uint256 tokens_bought);
    
    constructor(
        string memory _name,
        string memory _symbol,
        address[] memory _coins
    ) ERC20(_name, _symbol) {
        require(_coins.length >= 2, "Need at least 2 coins");
        
        for (uint256 i = 0; i < _coins.length; i++) {
            coins.push(IERC20(_coins[i]));
            balances.push(0);
        }
        
        _fee = 4; // 0.04% default fee
        _adminFee = 5000; // 50% of fee goes to admin
    }
    
    /**
     * @dev Get number of coins in the pool
     */
    function N_COINS() external view returns (uint256) {
        return coins.length;
    }
    
    /**
     * @dev Get coin at index
     */
    function getCoin(uint256 i) external view returns (address) {
        return address(coins[i]);
    }

    /**
     * @dev Get balance of coin at index
     */
    function getBalance(uint256 i) external view returns (uint256) {
        return balances[i];
    }
    
    /**
     * @dev Add liquidity to the pool
     */
    function add_liquidity(uint256[] calldata amounts, uint256 min_mint_amount) external returns (uint256) {
        require(amounts.length == coins.length, "Wrong number of amounts");
        
        uint256 totalValue = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0) {
                coins[i].transferFrom(msg.sender, address(this), amounts[i]);
                balances[i] += amounts[i];
                totalValue += amounts[i]; // Simplified: assume all coins have same value
            }
        }
        
        // Simplified LP token calculation
        uint256 lpTokens = totalValue;
        if (totalSupply() > 0) {
            // If pool already has liquidity, calculate proportional amount
            lpTokens = (totalValue * totalSupply()) / getTotalValue();
        }
        
        require(lpTokens >= min_mint_amount, "Slippage too high");
        
        _mint(msg.sender, lpTokens);
        emit AddLiquidity(msg.sender, amounts, lpTokens);
        
        return lpTokens;
    }
    
    /**
     * @dev Remove liquidity from the pool
     */
    function remove_liquidity(uint256 _amount, uint256[] calldata min_amounts) external returns (uint256[] memory) {
        require(_amount > 0, "Amount must be positive");
        require(balanceOf(msg.sender) >= _amount, "Insufficient LP tokens");
        require(min_amounts.length == coins.length, "Wrong number of min amounts");
        
        uint256[] memory amounts = new uint256[](coins.length);
        uint256 totalSupplyBefore = totalSupply();
        
        for (uint256 i = 0; i < coins.length; i++) {
            amounts[i] = (balances[i] * _amount) / totalSupplyBefore;
            require(amounts[i] >= min_amounts[i], "Slippage too high");
            
            balances[i] -= amounts[i];
            coins[i].transfer(msg.sender, amounts[i]);
        }
        
        _burn(msg.sender, _amount);
        emit RemoveLiquidity(msg.sender, _amount, amounts);
        
        return amounts;
    }
    
    /**
     * @dev Exchange coins
     */
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256) {
        require(i != j, "Cannot exchange same coin");
        require(i >= 0 && i < int128(int256(coins.length)), "Invalid coin index i");
        require(j >= 0 && j < int128(int256(coins.length)), "Invalid coin index j");
        require(dx > 0, "Amount must be positive");
        
        uint256 ui = uint256(int256(i));
        uint256 uj = uint256(int256(j));
        
        // Simplified exchange rate (1:1 minus fee)
        uint256 dy = (dx * (10000 - _fee)) / 10000;
        require(dy >= min_dy, "Slippage too high");
        require(balances[uj] >= dy, "Insufficient liquidity");
        
        coins[ui].transferFrom(msg.sender, address(this), dx);
        coins[uj].transfer(msg.sender, dy);
        
        balances[ui] += dx;
        balances[uj] -= dy;
        
        emit Exchange(msg.sender, i, dx, j, dy);
        return dy;
    }
    
    /**
     * @dev Get exchange rate for a trade
     */
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256) {
        require(i != j, "Cannot exchange same coin");
        require(dx > 0, "Amount must be positive");
        
        // Simplified: 1:1 exchange minus fee
        return (dx * (10000 - _fee)) / 10000;
    }
    
    /**
     * @dev Get virtual price of LP token
     */
    function get_virtual_price() external view returns (uint256) {
        if (totalSupply() == 0) return 1e18;
        return (getTotalValue() * 1e18) / totalSupply();
    }
    
    /**
     * @dev Get total value in the pool
     */
    function getTotalValue() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            total += balances[i];
        }
        return total;
    }
    
    /**
     * @dev Set fee (for testing)
     */
    function setFee(uint256 _newFee) external {
        require(_newFee <= 10000, "Fee too high");
        _fee = _newFee;
    }

    /**
     * @dev Add fees for testing
     */
    function addFees() external {
        // Simulate fee accumulation by minting LP tokens
        uint256 feeAmount = getTotalValue() / 1000; // 0.1% fee
        if (feeAmount > 0) {
            _mint(address(this), feeAmount);
        }
    }

    /**
     * @dev Add fees with specific amounts for testing
     */
    function addFees(uint256 amount0, uint256 amount1) external {
        // Simulate fee accumulation with specific amounts
        uint256 totalFees = amount0 + amount1;
        if (totalFees > 0) {
            _mint(address(this), totalFees / 100); // 1% of fees as LP tokens
        }
    }
}
