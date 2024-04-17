// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../extensions/TransferHelper.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract BaseSwap is ISwapProxy {
    ISwapRouter private swapRouter;
    ISwapFactory private factory;
    uint8 slippage;
    address owner;

    constructor(address _swapRouterAddress) {
        swapRouter = ISwapRouter(_swapRouterAddress);
        factory = ISwapFactory(swapRouter.factory());
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

        uint256 amountOutMinimum = getAmountOutMinimum(tokenIn, tokenOut, amountIn);
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
        console.log('amountInMaximum %s', amountInMaximum);
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountInMaximum
        );
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
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
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountInMaximum - amountIn);
        }

        return amountIn;
    }

    function getLiquidityOf(
        address token0,
        address token1
    ) external view returns (uint256) {
        ISwapPool pool = ISwapPool(factory.poolByPair(token0, token1));
        
        return pool.liquidity();
    }

    function getPoolAddressOf(
        address token0,
        address token1
    ) external view returns (address) {
        ISwapPool pool = ISwapPool(factory.poolByPair(token0, token1));
        
        return address(pool);
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
    ) public view returns (uint256 price) {
        uint8 token0Decimals = ERC20(token0).decimals();
        uint8 token1Decimals = ERC20(token1).decimals();

        ISwapPool pool = ISwapPool(factory.poolByPair(token0, token1));
        address poolToken0 = pool.token0();
        (uint160 sqrtPriceX96, , , , , , , ) = pool.globalState();

        if (poolToken0 != token0)
            return 10 ** (token0Decimals + token1Decimals) / sqrtPriceX96ToPrice(sqrtPriceX96, token1Decimals);

        return sqrtPriceX96ToPrice(sqrtPriceX96, token0Decimals);
    }

    function sqrtPriceX96ToPrice(
        uint160 sqrtPriceX96,
        uint8 tokenDecimals
    ) private pure returns (uint256) {
        return ((uint256(sqrtPriceX96) ** 2 * 10 ** tokenDecimals) / 2 ** 192);
    }

    function getAmountOutMinimum(
        address token0,
        address token1,
        uint256 amountIn) private view returns(uint256){
            return amountIn * getPriceOf(token0, token1) * (1e4 - slippage) / (10 ** (ERC20(token0).decimals() + 4)); 
    }

    function getAmountInMaximum(
        address token0,
        address token1,
        uint256 amountOut) private view returns(uint256){
            console.log('amountOut %s', amountOut);
            console.log('getPriceOf(token1, token0) %s', getPriceOf(token1, token0));
            return amountOut * getPriceOf(token1, token0) * (1e4 + slippage) / (10 ** (ERC20(token1).decimals() + 4)); 
    }

    function getSlippage(
    ) external view returns (uint256) {
        return slippage;
    }
}