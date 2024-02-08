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
import "../interfaces/IRewardVendor.sol";
import "../interfaces/IERC721Receiver.sol";
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract RockOnyxEthLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;

    IVenderLiquidityProxy internal ethLPProvider;
    IRewardVendor internal ethReward;
    ISwapProxy internal ethSwapProxy;

    address arb;
    address grail;
    address usd;
    address weth;
    address wstEth;
    address ethNftPositionAddress;

    EthLPState ethLPState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        ethLPState = EthLPState(0, 0, 0, 0, 0);
    }

    function ethLP_Initialize(
        address _LiquidityProviderAddress,
        address _rewardAddress,
        address _ethNftPositionAddress,
        address _swapAddress,
        address _usd,
        address _weth,
        address _wstEth,
        address _arb
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethLPProvider = IVenderLiquidityProxy(_LiquidityProviderAddress);
        ethReward = IRewardVendor(_rewardAddress);
        ethNftPositionAddress = _ethNftPositionAddress;
        ethSwapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        arb = _arb;
    }

    function depositToEthLiquidityStrategy(uint256 amount) internal {
        ethLPState.unAllocatedBalance += amount;
        console.log("ethLPState.unAllocatedBalance %s", ethLPState.unAllocatedBalance);
    }

    function mintEthLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(ethLPState.liquidity == 0, "POSITION_ALREADY_OPEN");
        
        _rebalanceEthLPAssets(ratio, decimals);

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

        ethLPState.tokenId = tokenId;
        ethLPState.liquidity = liquidity;
        ethLPState.lowerTick = lowerTick;
        ethLPState.upperTick = upperTick;

        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            ethLPState.tokenId
        );

        if(IERC20(wstEth).balanceOf(address(this)) > 0){
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }

       ethLPState.unAllocatedBalance += _ethLPSwapTo(weth, IERC20(weth).balanceOf(address(this)), usd);
       console.log("mintEthLPPosition unAllocatedBalance %s", ethLPState.unAllocatedBalance);
    }
    
    function increaseEthLPLiquidity(uint16 ratio, uint8 decimals) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(ethLPState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        _rebalanceEthLPAssets(ratio, decimals);

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
                ethLPState.tokenId,
                wstEth,
                IERC20(wstEth).balanceOf(address(this)),
                weth,
                IERC20(weth).balanceOf(address(this))
            );

        ethLPState.liquidity += liquidity;

        if(IERC20(wstEth).balanceOf(address(this)) > 0){
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }

        _ethLPSwapTo(weth, IERC20(weth).balanceOf(address(this)), usd);
    }

    function decreaseEthLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if(liquidity == 0){
            liquidity = ethLPState.liquidity;
        }

        _decreaseEthLPLiquidity(liquidity);
        if(IERC20(wstEth).balanceOf(address(this)) > 0){
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }
        
        ethLPState.unAllocatedBalance = _ethLPSwapTo(weth, IERC20(weth).balanceOf(address(this)), usd);
    }

    function closeEthLPRound() internal {
        if(ethLPState.tokenId == 0) return;
        ethLPProvider.collectAllFees(ethLPState.tokenId);
    }

    function acquireWithdrawalFundsEthLP(uint256 amount) internal returns (uint256){
        console.log("unAllocatedBalance %s", ethLPState.unAllocatedBalance);
        if(ethLPState.unAllocatedBalance >= amount){
            ethLPState.unAllocatedBalance -= amount;
            return amount;
        }

        uint256 unAllocatedBalance = ethLPState.unAllocatedBalance;
        uint256 amountToAcquire = amount - ethLPState.unAllocatedBalance;
        ethLPState.unAllocatedBalance = 0;

        uint128 liquidity = _amountToPoolLiquidity(amountToAcquire);
         _decreaseEthLPLiquidity(liquidity);
        if(IERC20(wstEth).balanceOf(address(this)) > 0){
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }
        
        return unAllocatedBalance + _ethLPSwapTo(weth, IERC20(weth).balanceOf(address(this)), usd);
    }

    function claimReward(address[] calldata users, address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        require(users.length > 0, "INVALID_CLAIM_USERS");
        require(tokens.length > 0, "INVALID_CLAIM_TOKENS");
        require(amounts.length > 0, "INVALID_CLAIM_AMOUNTS");
        require(proofs.length > 0, "INVALID_CLAIM_PROOFS");
       
        ethReward.claim(users, tokens, amounts, proofs);
    }

    function convertRewardToUsdc() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if(IERC20(arb).balanceOf(address(this)) > 0){
            ethLPState.unAllocatedBalance += _ethLPSwapTo(arb, IERC20(arb).balanceOf(address(this)), usd);
        }
    }

    function getTotalEthLPAssets() internal view returns (uint256) {
        if(ethLPState.liquidity == 0)
            return
                ethLPState.unAllocatedBalance +
                (IERC20(arb).balanceOf(address(this)) * _getArbPrice() +
                IERC20(wstEth).balanceOf(address(this)) * _getWstEthPrice()  +
                IERC20(weth).balanceOf(address(this)) * _getEthPrice()) / 1e18;

        int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
        (uint256 wstethAmount, uint256 wethAmount) = 
            LiquidityAmounts.getAmountsForLiquidityByTick(tick, ethLPState.lowerTick, ethLPState.upperTick, ethLPState.liquidity);
        
        // console.log("getTotalEthLPAssets %s", 
        //     ethLPState.unAllocatedBalance +
        //     (IERC20(arb).balanceOf(address(this)) * _getArbPrice() +
        //     (IERC20(wstEth).balanceOf(address(this)) + wstethAmount) * _getWstEthPrice()  +
        //     (IERC20(weth).balanceOf(address(this)) + wethAmount) * _getEthPrice()) / 1e18);
        return 
            ethLPState.unAllocatedBalance +
            (IERC20(arb).balanceOf(address(this)) * _getArbPrice() +
            (IERC20(wstEth).balanceOf(address(this)) + wstethAmount) * _getWstEthPrice()  +
            (IERC20(weth).balanceOf(address(this)) + wethAmount) * _getEthPrice()) / 1e18;
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

    function _getArbPrice() private view returns (uint256) {
        return ethSwapProxy.getPriceOf(arb, usd, 18, 6);
    }

    function _decreaseEthLPLiquidity(uint128 liquidity) private  returns (uint256 amount0, uint256 amount1){
        ethLPProvider.decreaseLiquidityCurrentRange(
            ethLPState.tokenId,
            liquidity
        );
        
        (amount0, amount1) = ethLPProvider.collectAllFees(
            ethLPState.tokenId
        );
        
        ethLPState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    function _getLiquidAsset() private view returns(uint256){
        int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
        (uint256 wstethAmount, uint256 wethAmount) = LiquidityAmounts.getAmountsForLiquidityByTick(tick, ethLPState.lowerTick, ethLPState.upperTick, ethLPState.liquidity);
        console.log("wstethAmount %s wstethAmount %s",wstethAmount, wethAmount);
        return (wstethAmount * _getWstEthPrice() + wethAmount * _getEthPrice()) / 1e18 ;
    }

    function _amountToPoolLiquidity(uint256 amount) private view returns (uint128) {
        return uint128(amount * ethLPState.liquidity / _getLiquidAsset());
    }

    function _rebalanceEthLPAssets(uint16 ratio, uint8 decimals) private {
        uint256 amountToSwap = ethLPState.unAllocatedBalance;
        ethLPState.unAllocatedBalance = 0;

        _ethLPSwapTo(usd, amountToSwap, weth);
        uint256 ethAmountToSwap = IERC20(weth).balanceOf(address(this)) * ratio / 10 ** decimals;
        _ethLPSwapTo(weth, ethAmountToSwap, wstEth);
    }
}
