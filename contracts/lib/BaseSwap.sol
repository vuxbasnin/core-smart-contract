// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../extensions/TransferHelper.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/IVenderPoolState.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseSwap is ISwapProxy {
    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouterAddress) {
        swapRouter = ISwapRouter(_swapRouterAddress);
    }

    function swapTo(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        return swapRouter.exactInputSingle(params);
    }

    function getPriceOf(address token0, address token1, uint8 token0Decimals, uint8 token1Decimals) external view returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,,) = swapRouter.getPool(token0, token1).globalState();
        return sqrtPriceX96ToPrice(sqrtPriceX96, token0Decimals, token1Decimals);
    }

    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 token1Decimals, uint8 token2Decimals) private pure returns(uint256){
        return uint256(sqrtPriceX96) ** 2 * 10 ** (token1Decimals - token2Decimals) /  2 ** 192;
    }
}
