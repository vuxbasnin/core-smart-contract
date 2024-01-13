// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IERC721Receiver.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../structs/RockOnyxStructs.sol";

struct UsdLiquidityAssets {
    uint256 unAllocatedUsdc;
    uint256 unAllocatedUsdce;
    uint256 allocatedUsdc;
    uint256 allocatedUsdce;
}

contract RockOynxUsdLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
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
        usdLiquidityAssets = UsdLiquidityAssets(0, 0, 0, 0);
        usdLPDepositState = DepositState(0, 0);
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

        _rebalanceUsdLPAssets();
    }

    function mintUsdLPPosition(
        int24 lowerTick,
        int24 upperTick
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPDepositState.tokenId == 0, "POSITION_ALREADY_OPEN");

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

        usdLiquidityAssets.allocatedUsdc += amount0;
        usdLiquidityAssets.allocatedUsdce += amount1;

        usdLPDepositState.tokenId = tokenId;
        usdLPDepositState.liquidity = liquidity;
    }

    function increaseUsdLPLiquidity() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPDepositState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

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

        usdLiquidityAssets.allocatedUsdc += amount0;
        usdLiquidityAssets.allocatedUsdce += amount1;
        usdLPDepositState.liquidity += liquidity;
    }

    function decreaseUsdLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (uint256 amount0, uint256 amount1) = _decreaseUsdLPLiquidity(liquidity);

        usdLiquidityAssets.unAllocatedUsdc += amount0;
        usdLiquidityAssets.unAllocatedUsdce += amount1;

        usdLPDepositState.liquidity -= liquidity;
    }

    function closeUsdLPRound() internal nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (uint256 amount0, uint256 amount1) = usdLPProvider.collectAllFees(
            usdLPDepositState.tokenId
        );
        usdLiquidityAssets.unAllocatedUsdc += amount0;
        usdLiquidityAssets.unAllocatedUsdce += amount1;
    }

    function acquireWithdrawalFundsUsdLP(uint256 amount) internal returns (uint256){
        uint128 liquidity = _amountToPoolLiquidity(amount);

        (uint256 usdcAmount, uint256 usdceAmount) = _decreaseUsdLPLiquidity(liquidity);

        uint256 usdcUsdeAmount = _swapTo(usdce, usdceAmount, usdc);

        return usdcAmount + usdcUsdeAmount;
    }

    function getTotalUsdLPAssets() internal view returns (uint256) {
        uint256 liquidity = usdSwapProxy.getLiquidityOf(usdc, usdce);
        address poolAddress = usdSwapProxy.getPoolAddressOf(usdc, usdce);
        uint256 poolAmount = IERC20(usdc).balanceOf(poolAddress)  + 
                                IERC20(usdce).balanceOf(poolAddress) * _getUsdcePrice();

        return usdLiquidityAssets.unAllocatedUsdc +
                usdLiquidityAssets.unAllocatedUsdce * _getUsdcePrice() +
                usdLPDepositState.liquidity * poolAmount / liquidity;
    }

    function _swapTo(
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
        (amount0, amount1) = usdLPProvider.decreaseLiquidityCurrentRange(
            usdLPDepositState.tokenId,
            liquidity
        );

        (uint256 amount0Fee, uint256 amount1Fee) = usdLPProvider.collectAllFees(
            usdLPDepositState.tokenId
        );

        usdLPDepositState.liquidity -= liquidity;

        return (amount0 + amount0Fee, amount1 + amount1Fee);
    }

    function _amountToPoolLiquidity(uint256 amount) private view returns (uint128) {
        uint256 liquidity = usdSwapProxy.getLiquidityOf(usdc, usdce);
        address poolAddress = usdSwapProxy.getPoolAddressOf(usdc, usdce);

        uint256 totalPoolBalance = IERC20(usdc).balanceOf(poolAddress) + 
                                IERC20(usdce).balanceOf(poolAddress) * _getUsdcePrice();

        return uint128(amount * liquidity / totalPoolBalance);
    }

    function _rebalanceUsdLPAssets() private {
        uint256 unAllocatedUsdcToSwap = (usdLiquidityAssets.unAllocatedUsdc *
            50) / 100;
        IERC20(usdc).approve(address(usdSwapProxy), unAllocatedUsdcToSwap);
        usdLiquidityAssets.unAllocatedUsdce += usdSwapProxy.swapTo(
            address(this),
            usdc,
            unAllocatedUsdcToSwap,
            usdce
        );
        usdLiquidityAssets.unAllocatedUsdc -= unAllocatedUsdcToSwap;
    }
}
