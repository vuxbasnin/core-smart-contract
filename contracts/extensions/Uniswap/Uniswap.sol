// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../lib/BaseSwap.sol";
import "../../interfaces/UniSwap/IUniswapRouter.sol";
import "../../interfaces/UniSwap/IUniSwapFactory.sol";


import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract UniSwap is BaseSwap {
    IUniSwapRouter private swapRouter;
    IUniswapV3Factory private factory;
    uint24 private poolFee = 1;  // 0.01%

    constructor(
        address _swapRouterAddress,
        address _factoryAddress,
        address _priceConsumer
    ) BaseSwap(_priceConsumer) {
        swapRouter = IUniSwapRouter(_swapRouterAddress);
        factory = IUniswapV3Factory(_factoryAddress);
    }

    function setPoolFee(uint24 fee) external {
        require(msg.sender == owner, "INVALID_ADMIN");
        require(fee <= 100, "Fee must be less than or equal to 100");
        poolFee = fee;
    }

    function swapTo(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external override returns (uint256) {
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
        IUniSwapRouter.ExactInputSingleParams memory params =
            IUniSwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        return swapRouter.exactInputSingle(params);
    }

    function swapToWithOutput(
        address recipient,
        address tokenIn,
        uint256 amountOut,
        address tokenOut
    ) external override returns (uint256) {
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

        IUniSwapRouter.ExactOutputSingleParams memory params =
            IUniSwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: recipient,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
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
    ) external override view returns (int24) {
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, poolFee));
        (, int24 tick, , , , , ) = pool.slot0();
        return tick;
    }
}
