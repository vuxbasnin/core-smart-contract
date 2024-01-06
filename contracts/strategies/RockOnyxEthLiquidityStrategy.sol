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

struct EthLiquidityAssets {
    uint256 unAllocatedEth;
    uint256 unAllocatedWstETH;
    uint256 allocatedEth;
    uint256 allocatedWstETH;
}

contract RockOnyxEthLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    EthLiquidityAssets private ethLiquidityAssets;
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
        ethLiquidityAssets = EthLiquidityAssets(0, 0, 0, 0);
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
        ethLiquidityAssets.unAllocatedEth += _swapTo(usd, _amount, weth);
    }

    function mintEthLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint256 ratio
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(depositState.tokenId == 0, "POSITION_ALREADY_OPEN");

        _rebalanceEthLPAssets(ratio);

        IERC20(wstEth).approve(
            address(ethLPProvider),
            ethLiquidityAssets.unAllocatedWstETH
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            ethLiquidityAssets.unAllocatedEth
        );

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = ethLPProvider.mintPosition(
                lowerTick,
                upperTick,
                wstEth,
                ethLiquidityAssets.unAllocatedWstETH,
                weth,
                ethLiquidityAssets.unAllocatedEth
            );

        ethLiquidityAssets.unAllocatedWstETH -= amount0;
        ethLiquidityAssets.unAllocatedEth -= amount1;

        ethLiquidityAssets.allocatedWstETH += amount0;
        ethLiquidityAssets.allocatedEth += amount1;

        depositState.tokenId = tokenId;
        depositState.liquidity = liquidity;
    }

    function increaseEthLPLiquidity(uint256 ratio) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(depositState.tokenId > 0, "POSITION_HAS_NOT_OPEN");

        _rebalanceEthLPAssets(ratio);

        IERC20(wstEth).approve(
            address(ethLPProvider),
            ethLiquidityAssets.unAllocatedWstETH
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            ethLiquidityAssets.unAllocatedEth
        );

        (uint128 liquidity, uint amount0, uint amount1) = ethLPProvider
            .increaseLiquidityCurrentRange(
                depositState.tokenId,
                wstEth,
                ethLiquidityAssets.unAllocatedWstETH,
                weth,
                ethLiquidityAssets.unAllocatedEth
            );

        ethLiquidityAssets.unAllocatedWstETH -= amount0;
        ethLiquidityAssets.unAllocatedEth -= amount1;

        ethLiquidityAssets.allocatedWstETH += amount0;
        ethLiquidityAssets.allocatedEth += amount1;
        depositState.liquidity += liquidity;
    }

    function decreaseEthLPLiquidity() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            depositState.tokenId
        );

        (uint256 amount0Fee, uint256 amount1Fee) = ethLPProvider.collectAllFees(
            depositState.tokenId
        );
        ethLiquidityAssets.unAllocatedWstETH += amount0Fee;
        ethLiquidityAssets.unAllocatedEth += amount1Fee;

        ethLPProvider.decreaseLiquidityCurrentRange(
            depositState.tokenId,
            depositState.liquidity
        );

        (uint256 amount0, uint256 amount1) = ethLPProvider.collectAllFees(
            depositState.tokenId
        );
        ethLiquidityAssets.unAllocatedWstETH += amount0;
        ethLiquidityAssets.unAllocatedEth += amount1;

        ethLiquidityAssets.allocatedWstETH -= amount0;
        ethLiquidityAssets.allocatedEth -= amount1;

        depositState.tokenId = 0;
        depositState.liquidity = 0;
    }

    function closeEthLPRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC721(ethNftPositionAddress).approve(
            address(ethLPProvider),
            depositState.tokenId
        );

        (uint256 amount0, uint256 amount1) = ethLPProvider.collectAllFees(
            depositState.tokenId
        );
        ethLiquidityAssets.unAllocatedWstETH += amount0;
        ethLiquidityAssets.unAllocatedEth += amount1;

        IERC721(ethNftPositionAddress).setApprovalForAll(
            address(ethLPProvider),
            false
        );
    }

    function getTotalEthLPAssets() internal view returns (uint256) {
        return
            ((ethLiquidityAssets.unAllocatedEth +
                ethLiquidityAssets.allocatedEth) * _getEthPrice()) /
            1e18 +
            ((ethLiquidityAssets.unAllocatedWstETH +
                ethLiquidityAssets.allocatedWstETH) * _getWstEthPrice()) /
            1e18;
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
        return ethSwapProxy.getPriceOf(weth, usd, 18, 6);
    }

    function _getWstEthPrice() private view returns (uint256) {
        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        return wstEthEthPrice * _getEthPrice();
    }

    function _rebalanceEthLPAssets(uint256 ratio) private {
        uint256 unAllocatedEthToSwap = (ethLiquidityAssets.unAllocatedEth *
            ratio) / 100;

        ethLiquidityAssets.unAllocatedWstETH += _swapTo(
            weth,
            unAllocatedEthToSwap,
            wstEth
        );
        ethLiquidityAssets.unAllocatedEth -= unAllocatedEthToSwap;
    }
}
