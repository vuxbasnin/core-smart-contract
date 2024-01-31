// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../lib/LiquidityAmounts.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IERC721Receiver.sol";
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract RockOnyxEthLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;

    IVenderLiquidityProxy internal ethLPProvider;
    ISwapProxy internal ethSwapProxy;

    address usd;
    address weth;
    address wstEth;
    address ethNftPositionAddress;

    DepositState depositState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        depositState = DepositState(0, 0, 0, 0);
    }

    function ethLP_Initialize(
        address _LiquidityProviderAddress,
        address _ethNftPositionAddress,
        address _swapAddress,
        address _usd,
        address _weth,
        address _wstEth
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLPProvider = IVenderLiquidityProxy(_LiquidityProviderAddress);
        ethNftPositionAddress = _ethNftPositionAddress;
        ethSwapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
    }

    function depositToEthLiquidityStrategy(uint256 _amount) internal {
        _ethLPSwapTo(usd, _amount, weth);
    }

    function mintEthLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint8 ratio
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(depositState.liquidity == 0, "POSITION_ALREADY_OPEN");
        
        _rebalanceEthLPAssets(ratio);
        
        IERC20(wstEth).approve(
            address(ethLPProvider),
            IERC20(wstEth).balanceOf(address(this))
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            IERC20(weth).balanceOf(address(this))
        );

        (uint256 tokenId, uint128 liquidity,,) = ethLPProvider.mintPosition(
                lowerTick,
                upperTick,
                wstEth,
                IERC20(wstEth).balanceOf(address(this)),
                weth,
                IERC20(weth).balanceOf(address(this))
            );

        depositState.tokenId = tokenId;
        depositState.liquidity = liquidity;
        depositState.lowerTick = lowerTick;
        depositState.upperTick = upperTick;

        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            depositState.tokenId
        );
    }

    function increaseEthLPLiquidity(uint8 ratio) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(depositState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        _rebalanceEthLPAssets(ratio);

        IERC20(wstEth).approve(
            address(ethLPProvider),
            IERC20(wstEth).balanceOf(address(this))
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            IERC20(weth).balanceOf(address(this))
        );

        (uint128 liquidity,,) = ethLPProvider
            .increaseLiquidityCurrentRange(
                depositState.tokenId,
                wstEth,
                IERC20(wstEth).balanceOf(address(this)),
                weth,
                IERC20(weth).balanceOf(address(this))
            );

        depositState.liquidity += liquidity;
        console.log("acquireWithdrawalFundsEthLP liquidity %s", liquidity);

    }

    function decreaseEthLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        _decreaseEthLPLiquidity(liquidity);
    }

    function closeEthLPRound() internal {
        if(depositState.tokenId == 0) return;
        ethLPProvider.collectAllFees(depositState.tokenId);
    }

    function acquireWithdrawalFundsEthLP(uint256 amount) internal returns (uint256){

        uint256 wstEthAmount1 = IERC20(wstEth).balanceOf(address(this));
        uint256 wethAmount1 = IERC20(weth).balanceOf(address(this));

        console.log("UNALLOCATED amount = %s", (wstEthAmount1 * _getWstEthPrice() + wethAmount1 * _getEthPrice()) / 1e18);

        uint128 liquidity = _amountToPoolLiquidity(amount);
        console.log("acquireWithdrawalFundsEthLP liquidity %s", liquidity);
        (uint256 wstEthAmount, uint256 wethAmount) = _decreaseEthLPLiquidity(liquidity);
        console.log("wstEthAmount %s %s", wstEthAmount, wethAmount);

        uint256 wstEthWethAmount = _ethLPSwapTo(wstEth, wstEthAmount, weth);
        uint256 wethUsdAmount = _ethLPSwapTo(weth, wethAmount + wstEthWethAmount, usd);
        
        return wethUsdAmount;
    }

    function getTotalEthLPAssets() internal view returns (uint256) {
        int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
        (uint256 wstethAmount, uint256 wethAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, depositState.lowerTick, depositState.upperTick, depositState.liquidity);
        
        uint256 totalAssets = 
            (IERC20(wstEth).balanceOf(address(this)) + wstethAmount) * _getWstEthPrice()  +
            (IERC20(weth).balanceOf(address(this)) + wethAmount) * _getEthPrice() ;
        console.log('getTotalEthLPAssets totalAssets: ', totalAssets / 1e18);

        return totalAssets / 1e18;
    }

    function _ethLPSwapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(ethSwapProxy), amountIn);
        return ethSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function _getEthPrice() private view returns (uint256) {
        return ethSwapProxy.getPriceOf(usd, weth, 6, 18);
    }

    function _getWstEthPrice() private view returns (uint256) {
        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        return wstEthEthPrice * _getEthPrice() / 1e18;
    }

    function _decreaseEthLPLiquidity(uint128 liquidity) private  returns (uint256 amount0, uint256 amount1){
        ethLPProvider.decreaseLiquidityCurrentRange(
            depositState.tokenId,
            liquidity
        );
        
        (amount0, amount1) = ethLPProvider.collectAllFees(
            depositState.tokenId
        );
        
        depositState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    function _getLiquidAsset() private view returns(uint256){
        int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
        (uint256 wstethAmount, uint256 wethAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, depositState.lowerTick, depositState.upperTick, depositState.liquidity);
        console.log("_getWstEthPrice()=%s", _getWstEthPrice());
        
        return (wstethAmount * _getWstEthPrice() + wethAmount * _getEthPrice()) / 1e18 ;
    }

    function _amountToPoolLiquidity(uint256 amount) private view returns (uint128) {
        console.log("depositState.liquidity %s _getLiquidAsset()=%s", depositState.liquidity, _getLiquidAsset());
        return uint128(amount * depositState.liquidity / _getLiquidAsset());
    }

    function _rebalanceEthLPAssets(uint8 ratio) private {
        uint256 unAllocatedEthToSwap = IERC20(weth).balanceOf(address(this)) * ratio / 100;
        
        _ethLPSwapTo(weth, unAllocatedEthToSwap, wstEth);
    }
}
