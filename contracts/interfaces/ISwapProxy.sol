// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ISwapProxy {
    function swapTo(address recipient, address tokenIn, uint256 amountIn, address tokenOut) external returns (uint256 amountOut);
    function getPriceOf(address token0, address token1, uint8 token0Decimals, uint8 token1Decimals) external view returns (uint256 price);
}
