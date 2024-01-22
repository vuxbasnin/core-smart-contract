// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract RockOnyxEthLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
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
        depositState = DepositState(0, 0);
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

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = ethLPProvider.mintPosition(
                lowerTick,
                upperTick,
                wstEth,
                IERC20(wstEth).balanceOf(address(this)),
                weth,
                IERC20(weth).balanceOf(address(this))
            );

        // console.log("-----mintEthLPPosition-----");
        // console.log("liquidity: ", liquidity);
        // console.log("wsteth mint amount: ", amount0);
        // console.log("weth mint amount: ", amount1);

        depositState.tokenId = tokenId;
        depositState.liquidity = liquidity;

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
        uint128 liquidity = _amountToPoolLiquidity(amount);

        (uint256 wstEthAmount, uint256 wethAmount) = _decreaseEthLPLiquidity(liquidity);

        uint256 wstEthUsdAmount = _ethLPSwapTo(wstEth, wstEthAmount, usd);
        uint256 wEthUsdAmount = _ethLPSwapTo(weth, wethAmount, usd);

        return wstEthUsdAmount + wEthUsdAmount;
    }

    function getTotalEthLPAssets() internal view returns (uint256) {
        uint256 poolLiquidity = ethSwapProxy.getLiquidityOf(wstEth, weth);
        address poolAddress = ethSwapProxy.getPoolAddressOf(wstEth, weth);

        // console.log("-----getTotalEthLPAssets-----");
        // console.log("poolLiquidity:", poolLiquidity);
        // console.log("depositState.liquidity:", depositState.liquidity);

        uint256 wstethPoolReturn = IERC20(wstEth).balanceOf(address(poolAddress)) * depositState.liquidity / poolLiquidity;
        uint256 wethPoolReturn = IERC20(weth).balanceOf(address(poolAddress)) * depositState.liquidity / poolLiquidity;
        
        // console.log("IERC20(wstEth).balanceOf(address(poolAddress)):", IERC20(wstEth).balanceOf(address(poolAddress)));
        // console.log("IERC20(weth).balanceOf(address(poolAddress)):", IERC20(weth).balanceOf(address(poolAddress)));
        // console.log("wstethPoolReturn:", wstethPoolReturn);
        // console.log("wethPoolReturn:", wethPoolReturn);

        uint256 amountLiquidityReturns = wstethPoolReturn * _getWstEthPrice() + 
                                wethPoolReturn * _getEthPrice();
        // console.log("amountLiquidityReturns:", amountLiquidityReturns);
        
        // console.log("weth asset", IERC20(weth).balanceOf(address(this)));
        // console.log("wsteth asset", IERC20(wstEth).balanceOf(address(this)));

        uint256 totalAssets = IERC20(weth).balanceOf(address(this)) * _getEthPrice() / 1e18 +
                IERC20(wstEth).balanceOf(address(this)) * _getWstEthPrice() / 1e18 +
                amountLiquidityReturns;
        
        // console.log("totalAssets:", totalAssets / 1e18);

        return totalAssets;

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

    function _amountToPoolLiquidity(uint256 amount) private view returns (uint128) {
        uint256 poolLiquidity = ethSwapProxy.getLiquidityOf(wstEth, weth);
        address poolAddress = ethSwapProxy.getPoolAddressOf(wstEth, weth);

        uint256 totalPoolBalance = IERC20(wstEth).balanceOf(poolAddress) * _getWstEthPrice() + 
                                IERC20(weth).balanceOf(poolAddress) * _getEthPrice();

        uint128 liquidity = uint128(amount * poolLiquidity / totalPoolBalance);
        // console.log("amount:", amount);
        // console.log("poolLiquidity:", poolLiquidity);
        // console.log("totalPoolBalance:", totalPoolBalance);
        // console.log("liquidity:", liquidity);
        return liquidity;
    }

    function _rebalanceEthLPAssets(uint8 ratio) private {
        uint256 unAllocatedEthToSwap = IERC20(weth).balanceOf(address(this)) * ratio / 100;
        
        _ethLPSwapTo(weth, unAllocatedEthToSwap, wstEth);
    }
}
