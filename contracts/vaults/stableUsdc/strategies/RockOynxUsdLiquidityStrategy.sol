// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../lib/LiquidityAmounts.sol";
import "../../../interfaces/IVenderLiquidityProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "../structs/RockOnyxStructs.sol";
import "hardhat/console.sol";

contract RockOynxUsdLiquidityStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;

    IVenderLiquidityProxy internal usdLPProvider;
    ISwapProxy internal usdSwapProxy;

    address usdc;
    address usdce;
    address usdNftPositionAddress;

    UsdLPState usdLPState;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        usdLPState = UsdLPState(0, 0, 0, 0, 0, 0);
    }

    function usdLP_Initialize(
        address _usdLPProviderAddress,
        address _usdNftPositionAddress,
        address _swapAddress,
        address _usdc,
        address _usdce
    ) internal {
        usdLPProvider = IVenderLiquidityProxy(_usdLPProviderAddress);
        usdNftPositionAddress = _usdNftPositionAddress;
        usdSwapProxy = ISwapProxy(_swapAddress);
        usdc = _usdc;
        usdce = _usdce;
    }

    /**
     * @dev Deposit an amount into the USD liquidity strategy.
     * @param _amount The amount to deposit into the liquidity strategy.
     */
    function depositToUsdLiquidityStrategy(uint256 _amount) internal {
        usdLPState.unAllocatedUsdcBalance += _amount;
    }

    /**
     * @dev Mint a USD liquidity position within the liquidity provider system.
     * @param lowerTick The lower tick of the price range for liquidity provision.
     * @param upperTick The upper tick of the price range for liquidity provision.
     * @param ratio Ratio used for rebalancing liquidity assets.
     * @param decimals Decimals used for rebalancing liquidity assets.
     */
    function mintUsdLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPState.liquidity == 0, "POS_ALR_OPEN");

        _rebalanceUsdLPAssets(ratio, decimals);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdcBalance
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdceBalance
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
                usdLPState.unAllocatedUsdcBalance,
                usdce,
                usdLPState.unAllocatedUsdceBalance
            );

        usdLPState.unAllocatedUsdcBalance -= amount0;
        usdLPState.unAllocatedUsdceBalance -= amount1;

        usdLPState.tokenId = tokenId;
        usdLPState.liquidity = liquidity;
        usdLPState.lowerTick = lowerTick;
        usdLPState.upperTick = upperTick;

        IERC721(usdNftPositionAddress).approve(
            address(usdLPProvider),
            usdLPState.tokenId
        );

        if (usdLPState.unAllocatedUsdceBalance > 0) {
            usdLPState.unAllocatedUsdcBalance += _usdLPSwapTo(
                usdce,
                usdLPState.unAllocatedUsdceBalance,
                usdc
            );
            usdLPState.unAllocatedUsdceBalance = 0;
        }
    }

    /**
     * @dev Increases liquidity in the USD liquidity position within the liquidity provider system.
     * @param ratio Ratio used for rebalancing liquidity assets.
     * @param decimals Decimals used for rebalancing liquidity assets.
     */
    function increaseUsdLPLiquidity(
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(usdLPState.liquidity > 0, "POS_NOT_OPEN");

        _rebalanceUsdLPAssets(ratio, decimals);

        IERC20(usdc).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdcBalance
        );
        IERC20(usdce).approve(
            address(usdLPProvider),
            usdLPState.unAllocatedUsdceBalance
        );

        (uint128 liquidity, uint amount0, uint amount1) = usdLPProvider
            .increaseLiquidityCurrentRange(
                usdLPState.tokenId,
                usdc,
                usdLPState.unAllocatedUsdcBalance,
                usdce,
                usdLPState.unAllocatedUsdceBalance
            );

        usdLPState.unAllocatedUsdcBalance -= amount0;
        usdLPState.unAllocatedUsdceBalance -= amount1;

        usdLPState.liquidity += liquidity;

        if (usdLPState.unAllocatedUsdceBalance > 0) {
            usdLPState.unAllocatedUsdcBalance += _usdLPSwapTo(
                usdce,
                usdLPState.unAllocatedUsdceBalance,
                usdc
            );
            usdLPState.unAllocatedUsdceBalance = 0;
        }
    }

    /**
     * @dev Decreases liquidity in the USD liquidity position within the liquidity provider system.
     * @param liquidity Amount of liquidity to decrease.
     */
    function decreaseUsdLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if (liquidity == 0) {
            liquidity = usdLPState.liquidity;
        }

        (uint256 usdcAmount, uint256 usdceAmount) = _decreaseUsdLPLiquidity(
            liquidity
        );

        uint256 swapUsdcAmount = usdceAmount > 0
            ? _usdLPSwapTo(usdce, usdceAmount, usdc)
            : 0;
        usdLPState.unAllocatedUsdcBalance += usdcAmount + swapUsdcAmount;
    }

    /**
     * @dev Closes the current USD liquidity provision round by collecting fees.
     */
    function closeUsdLPRound() internal {
        if (usdLPState.tokenId == 0) return;

        (uint256 amount0, uint256 amount1) = usdLPProvider.collectAllFees(
            usdLPState.tokenId
        );

        usdLPState.unAllocatedUsdcBalance += amount0;
        usdLPState.unAllocatedUsdceBalance += amount1;
    }

    /**
     * @dev Acquires withdrawal funds for the USD liquidity position.
     * @param amount Amount of funds to acquire.
     * @return The acquired amount of funds.
     */
    function acquireWithdrawalFundsUsdLP(
        uint256 amount
    ) internal returns (uint256) {
        if (usdLPState.unAllocatedUsdcBalance > amount) {
            usdLPState.unAllocatedUsdcBalance -= amount;
            return amount;
        }

        uint256 unAllocatedBalance = usdLPState.unAllocatedUsdcBalance;
        uint256 amountToAcquire = amount - usdLPState.unAllocatedUsdcBalance;
        usdLPState.unAllocatedUsdcBalance = 0;

        uint128 liquidity = _amountToUsdPoolLiquidity(amountToAcquire);
        liquidity = (liquidity > usdLPState.liquidity)
            ? usdLPState.liquidity
            : liquidity;
        (
            uint256 acquireUsdcAmount,
            uint256 acquireUsdceAmount
        ) = _decreaseUsdLPLiquidity(liquidity);
        uint256 usdcAmount = acquireUsdceAmount > 0
            ? _usdLPSwapTo(usdce, acquireUsdceAmount, usdc)
            : 0;

        return unAllocatedBalance + acquireUsdcAmount + usdcAmount;
    }

    /**
     * @dev Calculates the total assets in the USD liquidity position.
     * @return The total value of assets in the USD liquidity position.
     */
    function getTotalUsdLPAssets() internal view returns (uint256) {
        if (usdLPState.liquidity == 0)
            return
                usdLPState.unAllocatedUsdcBalance +
                (usdLPState.unAllocatedUsdceBalance * _getUsdcePrice()) /
                1e6;

        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = LiquidityAmounts
            .getAmountsForLiquidityByTick(
                tick,
                usdLPState.lowerTick,
                usdLPState.upperTick,
                usdLPState.liquidity
            );

        return
            usdLPState.unAllocatedUsdcBalance +
            usdcAmount +
            ((usdLPState.unAllocatedUsdceBalance + usdceAmount) *
                _getUsdcePrice()) /
            1e6;
    }

    /**
     * @dev Swaps an amount of one token for another in the USD liquidity position.
     * @param tokenIn Address of the input token.
     * @param amountIn Amount of input token to swap.
     * @param tokenOut Address of the output token.
     * @return amountOut of output token received after the swap.
     */
    function _usdLPSwapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(usdSwapProxy), amountIn);
        return usdSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    /**
     * @dev Retrieves the price of USD Coin Equivalent (USDCE) token.
     * @return The price of USDCE in USD Coin (USDC).
     */
    function _getUsdcePrice() private view returns (uint256) {
        uint256 usdc2Usdce = usdSwapProxy.getPriceOf(usdc, usdce);
        return 1e12 / usdc2Usdce;
    }

    /**
     * @dev Decreases liquidity in the USD liquidity position.
     * @param liquidity Amount of liquidity to decrease.
     * @return amount0 of tokens received after the decrease in liquidity.
     * @return amount1 of tokens received after the decrease in liquidity.
     */
    function _decreaseUsdLPLiquidity(
        uint128 liquidity
    ) private returns (uint256 amount0, uint256 amount1) {
        usdLPProvider.decreaseLiquidityCurrentRange(
            usdLPState.tokenId,
            liquidity
        );

        (amount0, amount1) = usdLPProvider.collectAllFees(usdLPState.tokenId);

        usdLPState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    /**
     * @dev Retrieves the liquid assets in the USD liquidity position.
     * @return The value of liquid assets in the USD liquidity position.
     */
    function _getLiquidityUsdPoolAsset() private view returns (uint256) {
        int24 tick = usdSwapProxy.getPoolCurrentTickOf(usdc, usdce);
        (uint256 usdcAmount, uint256 usdceAmount) = LiquidityAmounts
            .getAmountsForLiquidityByTick(
                tick,
                usdLPState.lowerTick,
                usdLPState.upperTick,
                usdLPState.liquidity
            );

        uint256 liquidityAssets = usdcAmount +
            (usdceAmount * _getUsdcePrice()) /
            1e6;

        return liquidityAssets;
    }

    /**
     * @dev Converts an amount of tokens to USD pool liquidity.
     * @param amount Amount of tokens to convert.
     * @return The corresponding pool liquidity amount.
     */
    function _amountToUsdPoolLiquidity(
        uint256 amount
    ) private view returns (uint128) {
        return
            uint128(
                (amount * usdLPState.liquidity) / _getLiquidityUsdPoolAsset()
            );
    }

    /**
     * @dev Rebalances assets in the USD liquidity position.
     * @param ratio Ratio used for rebalancing.
     * @param decimals Decimals used for ratio.
     */
    function _rebalanceUsdLPAssets(uint16 ratio, uint8 decimals) private {
        uint256 unAllocatedUsdcToSwap = (usdLPState.unAllocatedUsdcBalance *
            ratio) / 10 ** decimals;
        usdLPState.unAllocatedUsdcBalance -= unAllocatedUsdcToSwap;
        usdLPState.unAllocatedUsdceBalance += _usdLPSwapTo(
            usdc,
            unAllocatedUsdcToSwap,
            usdce
        );
    }

    /**
     * @dev Retrieves the current state of the USD liquidity position.
     * @return The current state of the USD liquidity position.
     */
    function getUsdLPState() external view returns (UsdLPState memory) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return usdLPState;
    }
}
