// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "../extensions/TransferHelper.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseSwap is ISwapProxy {
    ISwapRouter private swapRouter;
    ISwapFactory private factory;

    constructor(address _swapRouterAddress) {
        swapRouter = ISwapRouter(_swapRouterAddress);
        factory = ISwapFactory(swapRouter.factory());
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
        console.log("Test nek %s %s %s", tokenIn, tokenOut, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            });

        return swapRouter.exactInputSingle(params);
    }

    function getPriceOf(
        address token0,
        address token1,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) external view returns (uint256 price) {
        ISwapPool pool = ISwapPool(factory.poolByPair(token0, token1));
        address poolToken0 = pool.token0();
        (uint160 sqrtPriceX96, , , , , , , ) = pool.globalState();

        if (poolToken0 != token0)
            return sqrtPriceX96ToPrice(sqrtPriceX96, token1Decimals);

        // console.log(
        //     "token1 = %s; token2 = %s; sqrtPriceX96ToPrice = %s",
        //     token0,
        //     token1,
        //     sqrtPriceX96
        // );
        return sqrtPriceX96ToPrice(sqrtPriceX96, token0Decimals);
    }

    function sqrtPriceX96ToPrice(
        uint160 sqrtPriceX96,
        uint8 token1Decimals
    ) private pure returns (uint256) {
        return ((uint256(sqrtPriceX96) ** 2 * 10 ** token1Decimals) / 2 ** 192);
    }
}
