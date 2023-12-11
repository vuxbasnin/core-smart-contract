// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../interfaces/ISwapProxy.sol";

contract UniswapSwap is ISwapProxy {
    ISwapRouter public immutable swapRouter;

    // goerli testnet address: 
    // WETH9 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6
    // USDT 0x509Ee0d083DdF8AC028f2a56731412edD63223B9
    address private  WETH9; 
    address private  USDT;

    constructor(ISwapRouter _swapRouter, address _weth, address _usdt) {
        swapRouter = _swapRouter;
        WETH9 = _weth;
        USDT = _usdt;
    }

    function Swap(uint256 amountIn) external returns (uint256 amountOut) {
        TransferHelper.safeApprove(USDT, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDT,
                tokenOut: WETH9,
                fee: 0,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        return swapRouter.exactInputSingle(params);
    }
}