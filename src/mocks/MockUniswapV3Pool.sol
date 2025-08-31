// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockUniswapV3Pool
 * @dev Mock implementation of Uniswap V3 pool for testing
 */
contract MockUniswapV3Pool {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable fee;

    uint160 public sqrtPriceX96;
    int24 public tick;
    uint128 public liquidity;

    mapping(bytes32 => uint256) public positions;

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        fee = _fee;

        // Initialize with some default values
        sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        tick = 0;
        liquidity = 0;
    }

    /**
     * @dev Add liquidity to the pool
     */
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(tickLower < tickUpper, "Invalid tick range");
        require(amount > 0, "Amount must be positive");

        // Simplified calculation - in real Uniswap this is much more complex
        amount0 = uint256(amount) / 2;
        amount1 = uint256(amount) / 2;

        // Transfer tokens from sender
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        // Update position
        bytes32 positionKey = keccak256(abi.encodePacked(recipient, tickLower, tickUpper));
        positions[positionKey] += amount;

        // Update pool liquidity
        liquidity += amount;

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);

        return (amount0, amount1);
    }

    /**
     * @dev Remove liquidity from the pool
     */
    function burn(int24 tickLower, int24 tickUpper, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(tickLower < tickUpper, "Invalid tick range");
        require(amount > 0, "Amount must be positive");

        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        require(positions[positionKey] >= amount, "Insufficient liquidity");

        // Simplified calculation
        amount0 = uint256(amount) / 2;
        amount1 = uint256(amount) / 2;

        // Update position
        positions[positionKey] -= amount;

        // Update pool liquidity
        liquidity -= amount;

        // Transfer tokens back to sender
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);

        return (amount0, amount1);
    }

    /**
     * @dev Swap tokens
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "Amount cannot be zero");

        if (zeroForOne) {
            // Swapping token0 for token1
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountOut = (amountIn * 997) / 1000; // 0.3% fee

            token0.transferFrom(msg.sender, address(this), amountIn);
            token1.transfer(recipient, amountOut);

            amount0 = int256(amountIn);
            amount1 = -int256(amountOut);
        } else {
            // Swapping token1 for token0
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountOut = (amountIn * 997) / 1000; // 0.3% fee

            token1.transferFrom(msg.sender, address(this), amountIn);
            token0.transfer(recipient, amountOut);

            amount0 = -int256(amountOut);
            amount1 = int256(amountIn);
        }

        emit Swap(msg.sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick);

        return (amount0, amount1);
    }

    /**
     * @dev Get position info
     */
    function getPosition(bytes32 key) external view returns (uint256) {
        return positions[key];
    }

    /**
     * @dev Set sqrt price (for testing)
     */
    function setSqrtPriceX96(uint160 _sqrtPriceX96) external {
        sqrtPriceX96 = _sqrtPriceX96;
    }

    /**
     * @dev Set tick (for testing)
     */
    function setTick(int24 _tick) external {
        tick = _tick;
    }

    /**
     * @dev Get slot0 data
     */
    function slot0()
        external
        view
        returns (
            uint160 _sqrtPriceX96,
            int24 _tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (sqrtPriceX96, tick, 0, 1, 1, 0, true);
    }
}
