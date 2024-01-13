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
        _swapTo(usd, _amount, weth);
    }

    function mintEthLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint256 ratio
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

        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            depositState.tokenId
        );
    }

    function increaseEthLPLiquidity(uint256 ratio) external nonReentrant {
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
        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            depositState.tokenId
        );

        ethLPProvider.collectAllFees(depositState.tokenId);

        IERC721(ethNftPositionAddress).setApprovalForAll(
            address(ethLPProvider),
            false
        );
    }

    function acquireWithdrawalFundsEthLP(uint256 amount) internal returns (uint256){
        uint128 liquidity = _amountToPoolLiquidity(amount);

        (uint256 wstEthAmount, uint256 wethAmount) = _decreaseEthLPLiquidity(liquidity);

        uint256 wstEthUsdAmount = _swapTo(wstEth, wstEthAmount, usd);
        uint256 wEthUsdAmount = _swapTo(weth, wethAmount, usd);

        return wstEthUsdAmount + wEthUsdAmount;
    }

    function getTotalEthLPAssets() internal view returns (uint256) {
        uint256 liquidity = ethSwapProxy.getLiquidityOf(wstEth, weth);
        address poolAddress = ethSwapProxy.getPoolAddressOf(wstEth, weth);

        uint256 poolAmount = IERC20(wstEth).balanceOf(poolAddress) * _getWstEthPrice() + 
                                IERC20(weth).balanceOf(poolAddress) * _getEthPrice();

        return IERC20(weth).balanceOf(address(this)) * _getEthPrice() +
                IERC20(wstEth).balanceOf(address(this)) * _getWstEthPrice() +
                depositState.liquidity * poolAmount / liquidity;
    }

    function _swapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(ethSwapProxy), amountIn);
        return ethSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function _getEthPrice() private view returns (uint256) {
        return ethSwapProxy.getPriceOf(weth, usd, 18, 6) / 1e18;
    }

    function _getWstEthPrice() private view returns (uint256) {
        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        return wstEthEthPrice * _getEthPrice();
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
        uint256 liquidity = ethSwapProxy.getLiquidityOf(wstEth, weth);
        address poolAddress = ethSwapProxy.getPoolAddressOf(wstEth, weth);

        uint256 totalPoolBalance = IERC20(wstEth).balanceOf(poolAddress) * _getWstEthPrice() + 
                                IERC20(weth).balanceOf(poolAddress) * _getEthPrice();

        return uint128(amount * liquidity / totalPoolBalance);
    }

    function _rebalanceEthLPAssets(uint256 ratio) private {
        uint256 unAllocatedEthToSwap = IERC20(wstEth).balanceOf(address(this)) * ratio / 100;

        _swapTo(weth, unAllocatedEthToSwap, wstEth);
    }
}
