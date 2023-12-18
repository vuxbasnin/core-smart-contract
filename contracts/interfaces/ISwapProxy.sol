// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ISwapProxy {
    function swapTo(address recipient, address tokenIn, uint256 amountIn, address tokenOut, uint24 fee) external returns (uint256 amountOut);
}
