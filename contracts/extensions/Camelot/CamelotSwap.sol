// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../lib/BaseSwap.sol";
import "../../interfaces/CamelotSwap/ICamelotSwapRouter.sol";

contract CamelotSwap is BaseSwap {
    ICamelotSwapRouter private swapRouter;
    ICamelotSwapFactory private factory;

    constructor(
        address _admin,
        address _swapRouterAddress,
        address _priceConsumer
    ) BaseSwap(_admin, _priceConsumer) {
        swapRouter = ICamelotSwapRouter(_swapRouterAddress);
        factory = ICamelotSwapFactory(swapRouter.factory());
    }

    function swapTo(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external returns (uint256) {
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountIn
        );
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        uint256 amountOutMinimum = getAmountOutMinimum(
            tokenIn,
            tokenOut,
            amountIn
        );
        ICamelotSwapRouter.ExactInputSingleParams
            memory params = ICamelotSwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                limitSqrtPrice: 0
            });

        return swapRouter.exactInputSingle(params);
    }

    function swapToWithOutput(
        address recipient,
        address tokenIn,
        uint256 amountOut,
        address tokenOut
    ) external returns (uint256) {
        uint256 amountInMaximum = getAmountInMaximum(
            tokenIn,
            tokenOut,
            amountOut
        );
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountInMaximum
        );
        TransferHelper.safeApprove(
            tokenIn,
            address(swapRouter),
            amountInMaximum
        );

        ICamelotSwapRouter.ExactOutputSingleParams
            memory params = ICamelotSwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 0,
                recipient: recipient,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                limitSqrtPrice: 0
            });

        uint256 amountIn = swapRouter.exactOutputSingle(params);

        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(
                tokenIn,
                msg.sender,
                amountInMaximum - amountIn
            );
        }

        return amountIn;
    }

    function getPoolCurrentTickOf(
        address token0,
        address token1
    ) external view override returns (int24) {
        ICamelotSwapPool pool = ICamelotSwapPool(
            factory.poolByPair(token0, token1)
        );
        (, int24 tick, , , , , , ) = pool.globalState();
        return tick;
    }
}
