// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IGetPriceProxy.sol";
import "../extensions/RockOnyxAccessControl.sol";

struct EthLiquidityAsset {
    uint256 totalEth;
    uint256 totalWstETH;
    uint256 totalUSDT;
}

contract RockOnyxEthLiquidityStrategy is RockOnyxAccessControl, ReentrancyGuard{
    EthLiquidityAsset private ethLiquidityAsset;
    IVenderLiquidityProxy internal venderLiquidity;
    ISwapProxy internal swapProxy;
    IGetPriceProxy internal getPriceProxy;

    address usd;
    address weth;
    address wstEth;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(address _venderLiquidityAddress, address _swapAddress, address _getPriceAddress, address _usd, address _weth, address _wstEth) {
        venderLiquidity = IVenderLiquidityProxy(_venderLiquidityAddress);
        swapProxy = ISwapProxy(_swapAddress);
        getPriceProxy = IGetPriceProxy(_getPriceAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        ethLiquidityAsset = EthLiquidityAsset(0,0,0);
    }

    function depositToEthLiquidityStrategy(uint256 _amount) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLiquidityAsset.totalUSDT += _amount;
    }

    function mintPosition() external nonReentrant returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (tokenId, liquidity, amount0, amount1) = venderLiquidity.mintPosition(weth, ethLiquidityAsset.totalEth, wstEth, ethLiquidityAsset.totalWstETH);
        ethLiquidityAsset.totalEth -= amount0;
        ethLiquidityAsset.totalWstETH -= amount1;

        return (tokenId, liquidity, amount0, amount1);
    }

    function rePosition() external nonReentrant returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        
        (tokenId, liquidity, amount0, amount1) = venderLiquidity.mintPosition(weth, ethLiquidityAsset.totalEth, wstEth, ethLiquidityAsset.totalWstETH);
        ethLiquidityAsset.totalEth -= amount0;
        ethLiquidityAsset.totalWstETH -= amount1;

        return (tokenId, liquidity, amount0, amount1);
    }

    function swapTo(address tokenIn, uint256 amountIn, address tokenOut) private nonReentrant returns (uint256 amountOut) {
        return swapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function rebalancePool() external nonReentrant{
        uint256 ethWstEthPrice =  _getEthPrice() / _getWstEthPrice();
        uint256 ethUsdAmount = ethLiquidityAsset.totalUSDT * ethWstEthPrice;
        uint256 wstEthUsdAmount = ethLiquidityAsset.totalUSDT - ethUsdAmount;

        ethLiquidityAsset.totalEth += swapTo(usd, ethUsdAmount, weth);
        ethLiquidityAsset.totalWstETH += swapTo(usd, wstEthUsdAmount, wstEth);
        ethLiquidityAsset.totalUSDT = 0;
    }

    function _getEthPrice() private view returns(uint256){
        return getPriceProxy.getEthPrice();
    }

    function _getWstEthPrice() private view returns(uint256){
        return getPriceProxy.getWstEthPrice();
    }

    function getTotalAssets() internal view returns (uint256){
        return ethLiquidityAsset.totalUSDT + 
                ethLiquidityAsset.totalEth * _getEthPrice() + 
                ethLiquidityAsset.totalWstETH * _getWstEthPrice();
    }
}