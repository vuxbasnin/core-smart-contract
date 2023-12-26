// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IGetPriceProxy.sol";
import "../extensions/RockOnyxAccessControl.sol";

struct EthLiquidityAssets {
    uint256 totalUSDT;
    uint256 totalEth;
    uint256 totalWstETH;
    uint256 totalVenderEth;
    uint256 totalVenderWstETH;
}

contract RockOnyxEthLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    EthLiquidityAssets private ethLiquidityAssets;
    IVenderLiquidityProxy internal venderLiquidity;
    ISwapProxy internal swapProxy;
    IGetPriceProxy internal getPriceProxy;

    address usd;
    address weth;
    address wstEth;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(
        address _venderLiquidityAddress,
        address _swapAddress,
        address _getPriceAddress,
        address _usd,
        address _weth,
        address _wstEth
    ) {
        venderLiquidity = IVenderLiquidityProxy(_venderLiquidityAddress);
        swapProxy = ISwapProxy(_swapAddress);
        getPriceProxy = IGetPriceProxy(_getPriceAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        ethLiquidityAssets = EthLiquidityAssets(0, 0, 0 , 0, 0);
    }

    function depositToEthLiquidityStrategy(uint256 _amount) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLiquidityAssets.totalUSDT += _amount;
    }

    function rebalanceAssets() external nonReentrant{
        uint256 ethUsdAmount = ethLiquidityAssets.totalUSDT * _getEthWstEthPrice();
        uint256 wstEthUsdAmount = ethLiquidityAssets.totalUSDT - ethUsdAmount;

        ethLiquidityAssets.totalEth += swapTo(usd, ethUsdAmount, weth);
        ethLiquidityAssets.totalWstETH += swapTo(usd, wstEthUsdAmount, wstEth);
        ethLiquidityAssets.totalUSDT = 0;
    }

    function mintPosition() public nonReentrant returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (tokenId, liquidity, amount0, amount1) = venderLiquidity.mintPosition(weth, ethLiquidityAssets.totalEth, wstEth, ethLiquidityAssets.totalWstETH);
        ethLiquidityAssets.totalEth -= amount0;
        ethLiquidityAssets.totalWstETH -= amount1;

        ethLiquidityAssets.totalVenderEth += amount0;
        ethLiquidityAssets.totalVenderWstETH += amount1;

        return (tokenId, liquidity, amount0, amount1);
    }

    function rePosition() external nonReentrant returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return mintPosition();
    }

    function swapTo(address tokenIn, uint256 amountIn, address tokenOut) private nonReentrant returns (uint256 amountOut) {
        return swapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function _getEthPrice() private view returns (uint256) {
        return getPriceProxy.getEthPrice();
    }

    function _getWstEthPrice() private view returns (uint256) {
        return getPriceProxy.getWstEthPrice();
    }

    function _getEthWstEthPrice() private view returns (uint256) {
        return getPriceProxy.getEthWstEthPrice();
    }

    function getTotalAssets() internal view returns (uint256){
        return ethLiquidityAssets.totalUSDT + 
                (ethLiquidityAssets.totalEth + ethLiquidityAssets.totalVenderEth) * _getEthPrice() + 
                (ethLiquidityAssets.totalWstETH + ethLiquidityAssets.totalVenderWstETH) * _getWstEthPrice();
    }
}
