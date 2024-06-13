// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../lib/LiquidityAmounts.sol";
import "../../../interfaces/IVenderLiquidityProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "../../../interfaces/IRewardVendor.sol";
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract BaseLiquidityStrategy
{
    IVenderLiquidityProxy internal lpProvider;
    ISwapProxy internal baseSwapProxy;

    address usd;
    address nftPositionAddress;

    constructor() {}

    function BaseLP_Initialize(
        address _liquidityProviderAddress,
        address _nftPositionAddress,
        address _swapAddress,
        address _usd
    ) internal {
        lpProvider = IVenderLiquidityProxy(_liquidityProviderAddress);
        nftPositionAddress = _nftPositionAddress;
        baseSwapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
    }

    /**
     * @dev Mint an Ethereum liquidity position within the liquidity provider system.
     * @param lowerTick The lower tick of the price range for liquidity provision.
     * @param upperTick The upper tick of the price range for liquidity provision.
     */
    function mintLPPosition(
        int24 lowerTick,
        int24 upperTick,
        address token0,
        uint256 inAmount0,
        address token1,
        uint256 inAmount1
    ) internal returns(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1){
        IERC20(token0).approve(address(lpProvider), inAmount0);
        IERC20(token1).approve(address(lpProvider), inAmount1);

        (tokenId, liquidity, amount0, amount1) = lpProvider.mintPosition(
            lowerTick,
            upperTick,
            token0,
            inAmount0,
            token1,
            inAmount1
        );

        IERC721(nftPositionAddress).approve(address(lpProvider), tokenId);
    }

    function increaseLPLiquidity(
        uint256 tokenId,
        address token0,
        uint256 inAmount0,
        address token1,
        uint256 inAmount1
    ) internal returns(uint128 liquidity, uint256 amount0, uint256 amount1){
        IERC20(token0).approve(address(lpProvider), inAmount0);
        IERC20(token1).approve(address(lpProvider), inAmount1);

        (liquidity, amount0, amount1) = lpProvider.increaseLiquidityCurrentRange(
            tokenId,
            token0,
            inAmount0,
            token1,
            inAmount1
        );
    }

    /**
     * @dev Decreases liquidity in the Ethereum liquidity position within the liquidity provider system.
     * @param liquidity Amount of liquidity to decrease. If set to 0, decreases all liquidity.
     */
    function decreaseLPLiquidity(uint256 tokenId, uint128 liquidity) 
        internal returns(uint256 amount0, uint256 amount1) {
            (amount0, amount1) = _decreaseLPLiquidity(tokenId, liquidity);
    }

    /**
     * @dev Swaps an amount of one token for another in the Ethereum liquidity position.
     * @param tokenIn Address of the input token.
     * @param amountIn Amount of input token to swap.
     * @param tokenOut Address of the output token.
     * @return amountOut The amount of output token received after the swap.
     */
    function _swapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(baseSwapProxy), amountIn);
        return baseSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    /**
     * @dev Decreases liquidity in the Ethereum liquidity position.
     * @param liquidity Amount of liquidity to decrease.
     * @return amount0 The amounts of tokens received after the decrease in liquidity.
     * @return amount1 The amounts of tokens received after the decrease in liquidity.
     */
    function _decreaseLPLiquidity(
        uint256 tokenId,
        uint128 liquidity
    ) private returns (uint256 amount0, uint256 amount1) {
        lpProvider.decreaseLiquidityCurrentRange(
            tokenId,
            liquidity
        );

        (amount0, amount1) = lpProvider.collectAllFees(tokenId);

        return (amount0, amount1);
    }

    /**
     * @dev Closes the current Ethereum liquidity provision round by collecting fees.
     */
    function collectAllFees(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1){
        (amount0, amount1) = lpProvider.collectAllFees(tokenId);
    }

    /**
     * @dev Retrieves the liquid assets in the USD liquidity position.
     * @return The value of liquid assets in the USD liquidity position.
     */
    function _amountToPoolLiquidity(
        uint256 amount,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        address token0,
        address token1
    ) internal view returns (uint128) {
        int24 tick = baseSwapProxy.getPoolCurrentTickOf(token0, token1);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidityByTick(
                tick,
                lowerTick,
                upperTick,
                liquidity
            );

        uint256 liquidAsset = token0 == usd ?
            amount0 + amount1 * baseSwapProxy.getPriceOf(token1, usd) / 1e6 :
            (amount0 * baseSwapProxy.getPriceOf(token0, token1) / 1e18 + amount1) * baseSwapProxy.getPriceOf(token1, usd) / 1e18;
        return uint128(amount * liquidity / liquidAsset);
    }
}
