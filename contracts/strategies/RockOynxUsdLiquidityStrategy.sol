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

struct UsdLiquidityAssets {
    uint256 unAllocatedUsdc;
    uint256 unAllocatedUsdce;
}

contract RockOynxUsdLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;

    UsdLiquidityAssets private usdLiquidityAssets;
    IVenderLiquidityProxy internal usdLPProvider;
    ISwapProxy internal usdSwapProxy;

    address usdc;
    address usdce;
    address usdNftPositionAddress;

    DepositState usdLPDepositState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        usdLiquidityAssets = UsdLiquidityAssets(0, 0);
        usdLPDepositState = DepositState(0, 0,0,0);
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
        usdLiquidityAssets.unAllocatedUsdc += _amount;
    }

    function mintUsdLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint8 ratio
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPDepositState.tokenId == 0, "POSITION_ALREADY_OPEN");

        _rebalanceUsdLPAssets(ratio);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLiquidityAssets.unAllocatedUsdc
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLiquidityAssets.unAllocatedUsdce
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
                usdLiquidityAssets.unAllocatedUsdc,
                usdce,
                usdLiquidityAssets.unAllocatedUsdce
            );

        usdLiquidityAssets.unAllocatedUsdc -= amount0;
        usdLiquidityAssets.unAllocatedUsdce -= amount1;

        usdLPDepositState.tokenId = tokenId;
        usdLPDepositState.liquidity = liquidity;
        usdLPDepositState.lowerTick = lowerTick;
        usdLPDepositState.upperTick = upperTick;

         IERC721(usdNftPositionAddress).approve(
            address(usdLPProvider),
            usdLPDepositState.tokenId
        );
    }

    function increaseUsdLPLiquidity(uint8 ratio) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPDepositState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        _rebalanceUsdLPAssets(ratio);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLiquidityAssets.unAllocatedUsdc
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLiquidityAssets.unAllocatedUsdce
        );

        (uint128 liquidity, uint amount0, uint amount1) = usdLPProvider
            .increaseLiquidityCurrentRange(
                usdLPDepositState.tokenId,
                usdc,
                usdLiquidityAssets.unAllocatedUsdc,
                usdce,
                usdLiquidityAssets.unAllocatedUsdce
            );

        usdLiquidityAssets.unAllocatedUsdc -= amount0;
        usdLiquidityAssets.unAllocatedUsdce -= amount1;

        usdLPDepositState.liquidity += liquidity;
    }

    function decreaseUsdLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (uint256 amount0, uint256 amount1) = _decreaseUsdLPLiquidity(liquidity);

        usdLiquidityAssets.unAllocatedUsdc += amount0;
        usdLiquidityAssets.unAllocatedUsdce += amount1;
    }

    function closeUsdLPRound() internal  {
        if(usdLPDepositState.tokenId == 0) return;
        
        (uint256 amount0, uint256 amount1) = usdLPProvider.collectAllFees(
            usdLPDepositState.tokenId
        );

        usdLiquidityAssets.unAllocatedUsdc += amount0;
        usdLiquidityAssets.unAllocatedUsdce += amount1;
    }

    function acquireWithdrawalFundsUsdLP(uint256 amount) internal returns (uint256){
        uint128 liquidity = _amountToUsdPoolLiquidity(amount);

        (uint256 usdcAmount, uint256 usdceAmount) = _decreaseUsdLPLiquidity(liquidity);

        return usdcAmount + _usdLPSwapTo(usdce, usdceAmount, usdc);
    }

    function getTotalUsdLPAssets() internal view returns (uint256) {
        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, usdLPDepositState.lowerTick, usdLPDepositState.upperTick, usdLPDepositState.liquidity);
        
        uint256 totalAssets = usdLiquidityAssets.unAllocatedUsdc + usdcAmount +
            (usdLiquidityAssets.unAllocatedUsdce + usdceAmount) * _getUsdcePrice() / 1e6 ;
            
        return totalAssets;
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
            usdLPDepositState.tokenId,
            liquidity
        );

        (amount0, amount1) = usdLPProvider.collectAllFees(
            usdLPDepositState.tokenId
        );

        usdLPDepositState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    function _getLiquidityUsdPoolAsset() private view returns(uint256){
        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, usdLPDepositState.lowerTick, usdLPDepositState.upperTick, usdLPDepositState.liquidity);
        
        uint256 liquidityAssets = usdcAmount + usdceAmount * _getUsdcePrice() / 1e6;
        
        return liquidityAssets;
    }

    function _amountToUsdPoolLiquidity(uint256 amount) private view returns (uint128) {
         return uint128(amount * usdLPDepositState.liquidity / _getLiquidityUsdPoolAsset());
    }

    function _rebalanceUsdLPAssets(uint8 ratio) private {
        uint256 unAllocatedUsdcToSwap = usdLiquidityAssets.unAllocatedUsdc * ratio / 100;

        usdLiquidityAssets.unAllocatedUsdc -= unAllocatedUsdcToSwap;
        usdLiquidityAssets.unAllocatedUsdce += _usdLPSwapTo(usdc, unAllocatedUsdcToSwap, usdce);
    }
}
