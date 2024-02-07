// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/LiquidityAmounts.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IERC721Receiver.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract RockOynxUsdLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;

    IVenderLiquidityProxy internal usdLPProvider;
    ISwapProxy internal usdSwapProxy;

    address usdc;
    address usdce;
    address usdNftPositionAddress;

    UsdLPState usdLPState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        usdLPState = UsdLPState(0, 0, 0, 0, 0, 0);
    }

    function usdLP_Initialize(
        address _usdLPProviderAddress,
        address _usdNftPositionAddress,
        address _swapAddress,
        address _usdc,
        address _usdce
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        usdLPProvider = IVenderLiquidityProxy(_usdLPProviderAddress);
        usdNftPositionAddress = _usdNftPositionAddress;
        usdSwapProxy = ISwapProxy(_swapAddress);
        usdc = _usdc;
        usdce = _usdce;
    }

    function depositToUsdLiquidityStrategy(uint256 _amount) internal {
        usdLPState.unAllocatedUsdcBalance += _amount;
    }

    function mintUsdLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPState.tokenId == 0, "POSITION_ALREADY_OPEN");

        _rebalanceUsdLPAssets(ratio, decimals);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdcBalance
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdceBalance
        );

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = usdLPProvider.mintPosition(
                lowerTick,
                upperTick,
                usdc,
                usdLPState.unAllocatedUsdcBalance,
                usdce,
                usdLPState.unAllocatedUsdceBalance
            );

        usdLPState.unAllocatedUsdcBalance -= amount0;
        usdLPState.unAllocatedUsdceBalance -= amount1;

        usdLPState.tokenId = tokenId;
        usdLPState.liquidity = liquidity;
        usdLPState.lowerTick = lowerTick;
        usdLPState.upperTick = upperTick;

         IERC721(usdNftPositionAddress).approve(
            address(usdLPProvider),
            usdLPState.tokenId
        );
    }

    function increaseUsdLPLiquidity(uint16 ratio, uint8 decimals) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        _rebalanceUsdLPAssets(ratio, decimals);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdcBalance
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdceBalance
        );

        (uint128 liquidity, uint amount0, uint amount1) = usdLPProvider
            .increaseLiquidityCurrentRange(
                usdLPState.tokenId,
                usdc,
                usdLPState.unAllocatedUsdcBalance,
                usdce,
                usdLPState.unAllocatedUsdceBalance
            );

        usdLPState.unAllocatedUsdcBalance -= amount0;
        usdLPState.unAllocatedUsdceBalance -= amount1;

        usdLPState.liquidity += liquidity;
    }

    function decreaseUsdLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (uint256 amount0, uint256 amount1) = _decreaseUsdLPLiquidity(liquidity);

        usdLPState.unAllocatedUsdcBalance += amount0;
        usdLPState.unAllocatedUsdceBalance += amount1;
    }

    function closeUsdLPRound() internal  {
        if(usdLPState.tokenId == 0) return;
        
        (uint256 amount0, uint256 amount1) = usdLPProvider.collectAllFees(
            usdLPState.tokenId
        );

        usdLPState.unAllocatedUsdcBalance += amount0;
        usdLPState.unAllocatedUsdceBalance += amount1;
    }

    function acquireWithdrawalFundsUsdLP(uint256 amount) internal returns (uint256){
        if(usdLPState.unAllocatedUsdcBalance > amount){
            usdLPState.unAllocatedUsdcBalance -= amount;
            return amount;
        }

        console.log("amount %s", amount);
        console.log("usdLPState.unAllocatedUsdceBalance %s", usdLPState.unAllocatedUsdceBalance);
        console.log("usdLPState.unAllocatedUsdcBalance %s", usdLPState.unAllocatedUsdcBalance);

        uint256 amountToAcquire = amount - usdLPState.unAllocatedUsdcBalance - usdLPState.unAllocatedUsdceBalance;
        console.log("amountToAcquire %s", amountToAcquire);
        usdLPState.unAllocatedUsdcBalance = 0;
        uint128 liquidity = _amountToUsdPoolLiquidity(amountToAcquire);
        (uint256 usdcAmount, uint256 usdceAmount) = _decreaseUsdLPLiquidity(liquidity);
        console.log("usdcAmount %s, usdceAmount %s", usdcAmount, usdceAmount);
        uint256 swappedUsdc = _usdLPSwapTo(usdce, usdceAmount + usdLPState.unAllocatedUsdceBalance, usdc);
        console.log("swappedUsdc %s", swappedUsdc);
        uint256 totalUsdc = usdcAmount + usdLPState.unAllocatedUsdcBalance + swappedUsdc;
        console.log("totalUsdc %s", totalUsdc);
        return totalUsdc;
    }

    function getTotalUsdLPAssets() internal view returns (uint256) {
        if(usdLPState.liquidity == 0)
            return 
                usdLPState.unAllocatedUsdcBalance +
                usdLPState.unAllocatedUsdceBalance * _getUsdcePrice() / 1e6;

        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = 
            LiquidityAmounts.getAmountsForLiquidityByTick(tick, usdLPState.lowerTick, usdLPState.upperTick, usdLPState.liquidity);
        
        // console.log("getTotalUsdLPAssets %s", 
        //     usdLPState.unAllocatedUsdcBalance + usdcAmount +
        //     (usdLPState.unAllocatedUsdceBalance + usdceAmount) * _getUsdcePrice() / 1e6);

        return 
            usdLPState.unAllocatedUsdcBalance + usdcAmount +
            (usdLPState.unAllocatedUsdceBalance + usdceAmount) * _getUsdcePrice() / 1e6;
    }

    function _usdLPSwapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(usdSwapProxy), amountIn);
        return usdSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function _getUsdcePrice() private view returns (uint256) {
        uint256 usdc2Usdce = usdSwapProxy.getPriceOf(usdc, usdce, 6, 6);
        return 1e12 / usdc2Usdce;
    }

    function _decreaseUsdLPLiquidity(uint128 liquidity) private  returns (uint256 amount0, uint256 amount1){
        usdLPProvider.decreaseLiquidityCurrentRange(
            usdLPState.tokenId,
            liquidity
        );

        (amount0, amount1) = usdLPProvider.collectAllFees(
            usdLPState.tokenId
        );

        usdLPState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    function _getLiquidityUsdPoolAsset() private view returns(uint256){
        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, usdLPState.lowerTick, usdLPState.upperTick, usdLPState.liquidity);
        
        uint256 liquidityAssets = usdcAmount + usdceAmount * _getUsdcePrice() / 1e6;
        
        return liquidityAssets;
    }

    function _amountToUsdPoolLiquidity(uint256 amount) private view returns (uint128) {
         return uint128(amount * usdLPState.liquidity / _getLiquidityUsdPoolAsset());
    }

    function _rebalanceUsdLPAssets(uint16 ratio, uint8 decimals) private {
        uint256 unAllocatedUsdcToSwap = usdLPState.unAllocatedUsdcBalance * ratio / 10 ** decimals;

        usdLPState.unAllocatedUsdcBalance -= unAllocatedUsdcToSwap;
        usdLPState.unAllocatedUsdceBalance += _usdLPSwapTo(usdc, unAllocatedUsdcToSwap, usdce);
    }
}
