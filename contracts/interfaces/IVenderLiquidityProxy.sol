// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IVenderLiquidityProxy {
    function mintPosition(
        int24 lowerTick,
        int24 upperTick,
        address token0,
        uint256 amount0ToAdd,
        address token1,
        uint256 amount1ToAdd
    )
        external
        returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1);
    function increaseLiquidityCurrentRange(
        uint tokenId,
        address token0,
        uint amount0ToAdd,
        address token1,
        uint amount1ToAdd
    ) external returns (uint128 liquidity, uint amount0, uint amount1);
    function decreaseLiquidityCurrentRange(
        uint256 tokenId,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);
    function collectAllFees(
        uint tokenId
    ) external returns (uint amount0, uint amount1);
}
