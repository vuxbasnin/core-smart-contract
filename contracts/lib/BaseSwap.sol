// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../extensions/TransferHelper.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IPriceConsumerProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract BaseSwap is ISwapProxy {
    ISwapRouter private swapRouter;
    ISwapFactory private factory;
    IPriceConsumerProxy private priceConsumer;
    uint8 slippage;
    address owner;

    constructor(
        address _swapRouterAddress,
        address _priceConsumer
        ) {
        swapRouter = ISwapRouter(_swapRouterAddress);
        factory = ISwapFactory(swapRouter.factory());
        priceConsumer = IPriceConsumerProxy(_priceConsumer);
        slippage = 50;
        owner = msg.sender;
    }

    // slippage decimals: 4 ---- ex: 50 mean 0.5%
    function setSlippage(uint8 _slippage) external {
        require(msg.sender == owner, "INVALID_ADMIN");
        slippage = _slippage;
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
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
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
        uint256 amountInMaximum = getAmountInMaximum(tokenIn, tokenOut, amountOut);
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

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
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
    ) external view returns (int24) {
        ISwapPool pool = ISwapPool(factory.poolByPair(token0, token1));
        (, int24 tick, , , , , , ) = pool.globalState();
        return tick;
    }

    function getPriceOf(
        address token0,
        address token1
    ) external view returns (uint256) {
        return priceConsumer.getPriceOf(token0, token1);
    }

    function getAmountOutMinimum(
        address token0,
        address token1,
        uint256 amountIn) private view returns(uint256){
            return amountIn * priceConsumer.getPriceOf(token0, token1) * (1e4 - slippage) / (10 ** (ERC20(token0).decimals() + 4));
    }

    function getAmountInMaximum(
        address token0,
        address token1,
        uint256 amountOut) private view returns(uint256){
            return amountOut * priceConsumer.getPriceOf(token1, token0) * (1e4 + slippage) / (10 ** (ERC20(token1).decimals() + 4));
    }

    function getSlippage() external view returns (uint256) {
        return slippage;
    }
}
