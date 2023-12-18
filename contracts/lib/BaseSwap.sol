// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../extensions/TransferHelper.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ISwapRouter.sol";

contract BaseSwap is ISwapProxy {
    ISwapRouter public immutable swapRouter;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    function swapTo(address recipient, address tokenIn, uint256 amountIn, address tokenOut, uint24 fee) external returns (uint256 amountOut) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        return swapRouter.exactInputSingle(params);
    }
}