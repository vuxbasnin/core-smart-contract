// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IVenderLiquidityProxy {
    function mintPosition(address token0, uint256 amount0ToAdd, address token1, uint256 amount1ToAdd) external returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1);
}
