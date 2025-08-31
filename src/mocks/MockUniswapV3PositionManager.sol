// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockUniswapV3PositionManager
 * @dev Mock implementation of Uniswap V3 Position Manager for testing
 */
contract MockUniswapV3PositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    uint256 private nextTokenId = 1;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint128) public liquidityOf;

    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /**
     * @dev Mint a new position
     */
    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "Transaction too old");

        tokenId = nextTokenId++;
        liquidity = uint128((params.amount0Desired + params.amount1Desired) / 2);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        ownerOf[tokenId] = params.recipient;
        liquidityOf[tokenId] = liquidity;

        // Transfer tokens from sender
        IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);

        return (tokenId, liquidity, amount0, amount1);
    }

    /**
     * @dev Increase liquidity for a position
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "Transaction too old");
        require(ownerOf[params.tokenId] == msg.sender, "Not owner");

        liquidity = uint128((params.amount0Desired + params.amount1Desired) / 2);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        liquidityOf[params.tokenId] += liquidity;

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);

        return (liquidity, amount0, amount1);
    }

    /**
     * @dev Decrease liquidity for a position
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "Transaction too old");
        require(ownerOf[params.tokenId] == msg.sender, "Not owner");
        require(liquidityOf[params.tokenId] >= params.liquidity, "Insufficient liquidity");

        liquidityOf[params.tokenId] -= params.liquidity;

        // Simplified calculation
        amount0 = uint256(params.liquidity) / 2;
        amount1 = uint256(params.liquidity) / 2;

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);

        return (amount0, amount1);
    }

    /**
     * @dev Collect fees for a position
     */
    function collect(CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        require(ownerOf[params.tokenId] == msg.sender, "Not owner");

        // Simplified fee collection
        amount0 = uint256(params.amount0Max) / 10; // 10% of max as fees
        amount1 = uint256(params.amount1Max) / 10;

        return (amount0, amount1);
    }

    /**
     * @dev Get position info
     */
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        uint128 positionLiquidity = liquidityOf[tokenId];
        return (
            0, // nonce
            address(0), // operator
            address(0), // token0
            address(0), // token1
            3000, // fee (0.3%)
            -887220, // tickLower
            887220, // tickUpper
            positionLiquidity, // liquidity
            0, // feeGrowthInside0LastX128
            0, // feeGrowthInside1LastX128
            0, // tokensOwed0
            0 // tokensOwed1
        );
    }
}
