// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IVenderLiquidityProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/IERC721Receiver.sol";
import "../extensions/RockOnyxAccessControl.sol";

struct EthLiquidityAssets {
    uint256 unAllocatedUSD;
    uint256 unAllocatedEth;
    uint256 unAllocatedWstETH;
    uint256 allocatedEth;
    uint256 allocatedWstETH;
}

struct DepositState {
    uint256 tokenId;
    uint128 liquidity;
}

contract RockOnyxEthLiquidityStrategy is
    IERC721Receiver,
    RockOnyxAccessControl,
    ReentrancyGuard
{
    EthLiquidityAssets private ethLiquidityAssets;
    IVenderLiquidityProxy internal venderLiquidity;
    ISwapProxy internal swapProxy;

    address usd;
    address weth;
    address wstEth;
    address venderNftPositionAddress;

    DepositState depositState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(
        address _venderLiquidityAddress,
        address _venderNftPositionAddress,
        address _swapAddress,
        address _usd,
        address _weth,
        address _wstEth
    ) {
        venderLiquidity = IVenderLiquidityProxy(_venderLiquidityAddress);
        venderNftPositionAddress = _venderNftPositionAddress;
        swapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        ethLiquidityAssets = EthLiquidityAssets(0, 0, 0 , 0, 0);
        depositState = DepositState(0, 0);
    }

     function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {
    }

    function depositToEthLiquidityStrategy(uint256 _amount) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLiquidityAssets.unAllocatedUSD += _amount;

        _rebalanceAssets(50);
    }

    function mintPosition(int24 lowerTick, int24 upperTick) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        require(depositState.tokenId == 0, "POSITION_ALREADY_OPEN");

        IERC20(wstEth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedWstETH);
        IERC20(weth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedEth);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
             venderLiquidity.mintPosition(lowerTick, upperTick, wstEth, ethLiquidityAssets.unAllocatedWstETH, weth, ethLiquidityAssets.unAllocatedEth);

        ethLiquidityAssets.unAllocatedWstETH -= amount0;
        ethLiquidityAssets.unAllocatedEth -= amount1;

        ethLiquidityAssets.allocatedWstETH += amount0;
        ethLiquidityAssets.allocatedEth += amount1;

        depositState.tokenId = tokenId;
        depositState.liquidity = liquidity;
    }
    
    function increaseLiquidity(
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(depositState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        IERC20(wstEth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedWstETH);
        IERC20(weth).approve(address(venderLiquidity), ethLiquidityAssets.unAllocatedEth);
        
       (uint128 liquidity, uint amount0, uint amount1) = venderLiquidity.increaseLiquidityCurrentRange(depositState.tokenId, wstEth, ethLiquidityAssets.unAllocatedWstETH, weth, ethLiquidityAssets.unAllocatedEth);
        
        ethLiquidityAssets.unAllocatedWstETH -= amount0;
        ethLiquidityAssets.unAllocatedEth -= amount1;

        ethLiquidityAssets.allocatedWstETH += amount0;
        ethLiquidityAssets.allocatedEth += amount1;
        depositState.liquidity += liquidity;
    }

    function decreaseLiquidity(
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        IERC20(venderNftPositionAddress).approve(address(venderLiquidity), depositState.tokenId);

        (uint256 amount0Fee, uint256 amount1Fee) = venderLiquidity.collectAllFees(depositState.tokenId);
        ethLiquidityAssets.unAllocatedWstETH += amount0Fee;
        ethLiquidityAssets.unAllocatedEth += amount1Fee;

       venderLiquidity.decreaseLiquidityCurrentRange(depositState.tokenId, depositState.liquidity);

       (uint256 amount0, uint256 amount1) = venderLiquidity.collectAllFees(depositState.tokenId);
        ethLiquidityAssets.unAllocatedWstETH += amount0;
        ethLiquidityAssets.unAllocatedEth += amount1;

        ethLiquidityAssets.allocatedWstETH -= amount0;
        ethLiquidityAssets.allocatedEth -= amount1;

        depositState.tokenId = 0;
        depositState.liquidity = 0;
    }

    function collectAllFees() public nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC721(venderNftPositionAddress).approve(address(venderLiquidity), depositState.tokenId);
        
        (uint256 amount0, uint256 amount1) = venderLiquidity.collectAllFees(depositState.tokenId);
        ethLiquidityAssets.unAllocatedWstETH += amount0;
        ethLiquidityAssets.unAllocatedEth += amount1;

        IERC721(venderNftPositionAddress).setApprovalForAll(address(venderLiquidity), false);
    }

    function swapTo(address tokenIn, uint256 amountIn, address tokenOut) private returns (uint256 amountOut) {
         IERC20(tokenIn).approve(address(swapProxy), amountIn);

        return swapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function getTotalAssets() internal view returns (uint256){
        return ethLiquidityAssets.unAllocatedUSD + 
                (ethLiquidityAssets.unAllocatedEth + ethLiquidityAssets.allocatedEth) * _getEthPrice() + 
                (ethLiquidityAssets.unAllocatedWstETH + ethLiquidityAssets.allocatedWstETH) * _getWstEthPrice();
    }

    function _getEthPrice() private view returns (uint256) {
        return swapProxy.getPriceOf(weth, usd, 18 , 6);
    }

    function _getWstEthPrice() private view returns (uint256) {
        uint256 wstEthEthPrice = swapProxy.getPriceOf(wstEth, weth, 18, 18);
        return wstEthEthPrice * _getEthPrice();
    }

    function _rebalanceAssets(uint256 ratio) private {
        uint256 ethUsdAmount = ethLiquidityAssets.unAllocatedUSD * ratio / 100;
        uint256 wstEthUsdAmount = ethLiquidityAssets.unAllocatedUSD - ethUsdAmount;
        console.log("ethUsdAmount %s", ethUsdAmount);
        console.log("wstEthUsdAmount %s", wstEthUsdAmount);

        ethLiquidityAssets.unAllocatedEth += swapTo(usd, ethUsdAmount, weth);
        ethLiquidityAssets.unAllocatedWstETH += swapTo(usd, wstEthUsdAmount, wstEth);
        ethLiquidityAssets.unAllocatedUSD = 0;

        console.log("unAllocatedEth %s", ethLiquidityAssets.unAllocatedEth);
        console.log("unAllocatedWstETH %s", ethLiquidityAssets.unAllocatedWstETH);
    }
}
