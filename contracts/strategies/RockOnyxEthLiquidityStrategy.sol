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
    uint256 unAllocatedUSDT;
    uint256 unAllocatedEth;
    uint256 unAllocatedWstETH;
    uint256 allocatedEth;
    uint256 allocatedWstETH;
}

struct DepositState {
    uint256 tokenId;
    uint128 liquidity;
    uint256 token0Amount;
    uint256 token1Amount;
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

    DepositState depositState;

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
        depositState = DepositState(0, 0, 0, 0);
    }

    function depositToEthLiquidityStrategy(uint256 _amount) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLiquidityAssets.unAllocatedUSDT += _amount;
    }

    function rebalanceAssets() external nonReentrant{
        uint256 ethUsdAmount = ethLiquidityAssets.unAllocatedUSDT * _getEthWstEthPrice();
        uint256 wstEthUsdAmount = ethLiquidityAssets.unAllocatedUSDT - ethUsdAmount;

        ethLiquidityAssets.unAllocatedEth += swapTo(usd, ethUsdAmount, weth);
        ethLiquidityAssets.unAllocatedWstETH += swapTo(usd, wstEthUsdAmount, wstEth);
        ethLiquidityAssets.unAllocatedUSDT = 0;
    }

    function mintPosition() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC20(weth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedEth);
        IERC20(wstEth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedWstETH);
        
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = venderLiquidity.mintPosition(weth, ethLiquidityAssets.unAllocatedEth, wstEth, ethLiquidityAssets.unAllocatedWstETH);
        ethLiquidityAssets.unAllocatedEth -= amount0;
        ethLiquidityAssets.unAllocatedWstETH -= amount1;

        ethLiquidityAssets.allocatedEth += amount0;
        ethLiquidityAssets.allocatedWstETH += amount1;

        depositState.tokenId = tokenId;
        depositState.liquidity = liquidity;
        depositState.token0Amount = amount0;
        depositState.token1Amount = amount1;
    }

    function collectAllFees(uint tokenId) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        (uint256 amount0, uint256 amount1) = venderLiquidity.collectAllFees(address(this), tokenId);
        ethLiquidityAssets.unAllocatedEth += amount0;
        ethLiquidityAssets.unAllocatedWstETH += amount1;
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
        return ethLiquidityAssets.unAllocatedUSDT + 
                (ethLiquidityAssets.unAllocatedEth + ethLiquidityAssets.allocatedEth) * _getEthPrice() + 
                (ethLiquidityAssets.unAllocatedWstETH + ethLiquidityAssets.allocatedWstETH) * _getWstEthPrice();
    }
}
