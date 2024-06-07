// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../lib/LiquidityAmounts.sol";
import "../../../interfaces/IVenderLiquidityProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "../../../interfaces/IRewardVendor.sol";
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
        ethLPProvider = IVenderLiquidityProxy(_LiquidityProviderAddress);
        ethReward = IRewardVendor(_rewardAddress);
        ethNftPositionAddress = _ethNftPositionAddress;
        ethSwapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        arb = _arb;
    }

    /**
     * @dev Deposit an amount into the Ethereum liquidity strategy.
     * @param amount The amount to deposit into the Ethereum liquidity strategy.
     */
    function depositToEthLiquidityStrategy(uint256 amount) internal {
        ethLPState.unAllocatedBalance += amount;
    }

    /**
     * @dev Mint an Ethereum liquidity position within the liquidity provider system.
     * @param lowerTick The lower tick of the price range for liquidity provision.
     * @param upperTick The upper tick of the price range for liquidity provision.
     * @param ratio Ratio used for rebalancing liquidity assets.
     * @param decimals Decimals used for rebalancing liquidity assets.
     */
    function mintEthLPPosition(
        int24 lowerTick,
        int24 upperTick,
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(ethLPState.liquidity == 0, "POS_ALR_OPEN");
        _rebalanceEthLPAssets(ratio, decimals);
        IERC20(wstEth).approve(
            address(ethLPProvider),
            IERC20(wstEth).balanceOf(address(this))
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            IERC20(weth).balanceOf(address(this))
        );

        (uint256 tokenId, uint128 liquidity, , ) = ethLPProvider.mintPosition(
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

        if (IERC20(wstEth).balanceOf(address(this)) > 0) {
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }
    }

    /**
     * @dev Increases liquidity in the Ethereum liquidity position within the liquidity provider system.
     * @param ratio Ratio used for rebalancing liquidity assets.
     * @param decimals Decimals used for rebalancing liquidity assets.
     */
    function increaseEthLPLiquidity(
        uint16 ratio,
        uint8 decimals
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(ethLPState.liquidity > 0, "POS_NOT_OPEN");
        _rebalanceEthLPAssets(ratio, decimals);
        IERC20(wstEth).approve(
            address(ethLPProvider),
            IERC20(wstEth).balanceOf(address(this))
        );
        IERC20(weth).approve(
            address(ethLPProvider),
            IERC20(weth).balanceOf(address(this))
        );

        (uint128 liquidity, , ) = ethLPProvider.increaseLiquidityCurrentRange(
            ethLPState.tokenId,
            wstEth,
            IERC20(wstEth).balanceOf(address(this)),
            weth,
            IERC20(weth).balanceOf(address(this))
        );

        ethLPState.liquidity += liquidity;

        if (IERC20(wstEth).balanceOf(address(this)) > 0) {
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }
    }

    /**
     * @dev Decreases liquidity in the Ethereum liquidity position within the liquidity provider system.
     * @param liquidity Amount of liquidity to decrease. If set to 0, decreases all liquidity.
     */
    function decreaseEthLPLiquidity(uint128 liquidity) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        if (liquidity == 0) {
            liquidity = ethLPState.liquidity;
        }
        _decreaseEthLPLiquidity(liquidity);
        if (IERC20(wstEth).balanceOf(address(this)) > 0) {
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }
        ethLPState.unAllocatedBalance += _ethLPSwapTo(
            weth,
            IERC20(weth).balanceOf(address(this)),
            usd
        );
    }

    /**
     * @dev Closes the current Ethereum liquidity provision round by collecting fees.
     */
    function closeEthLPRound() internal {
        if (ethLPState.liquidity == 0) return;
        ethLPProvider.collectAllFees(ethLPState.tokenId);
    }

    /**
     * @dev Closes the current Ethereum liquidity provision round by collecting fees.
     */
    function acquireWithdrawalFundsEthLP(
        uint256 amount
    ) internal returns (uint256) {
        uint256 unAllocatedBalance = ethLPState.unAllocatedBalance;
        if (ethLPState.unAllocatedBalance >= amount) {
            ethLPState.unAllocatedBalance -= amount;
            return amount;
        }
        ethLPState.unAllocatedBalance = 0;
        uint256 unAllocatedAllAssetBalance = unAllocatedBalance +
            (IERC20(weth).balanceOf(address(this)) *
                ethSwapProxy.getPriceOf(weth, usd)) /
            1e18;

        if (unAllocatedAllAssetBalance > amount) {
            _ethLPSwapTo(
                weth,
                ((amount - unAllocatedBalance) * 1e6) /
                    ethSwapProxy.getPriceOf(weth, usd),
                usd
            );
            return amount;
        }

        uint256 amountToAcquire = amount - unAllocatedAllAssetBalance;
        uint128 liquidity = _amountToPoolLiquidity(amountToAcquire);
        liquidity = (liquidity > ethLPState.liquidity)
            ? ethLPState.liquidity
            : liquidity;
        _decreaseEthLPLiquidity(liquidity);
        if (IERC20(wstEth).balanceOf(address(this)) > 0) {
            _ethLPSwapTo(wstEth, IERC20(wstEth).balanceOf(address(this)), weth);
        }

        return
            unAllocatedBalance +
            _ethLPSwapTo(weth, IERC20(weth).balanceOf(address(this)), usd);
    }

    /**
     * @dev Claims rewards for specified users from the Ethereum reward contract.
     * @param users Addresses of the users to claim rewards for.
     * @param tokens Addresses of the tokens to claim as rewards.
     * @param amounts Amounts of tokens to claim as rewards.
     * @param proofs Merkle proofs for the claimed rewards.
     */
    function claimReward(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        ethReward.claim(users, tokens, amounts, proofs);
    }

    /**
     * @dev Converts rewards from ARB token to USDC token.
     */
    function convertRewardToUsdc() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        ethLPState.unAllocatedBalance += _ethLPSwapTo(
            arb,
            IERC20(arb).balanceOf(address(this)),
            usd
        );
    }

    /**
     * @dev Calculates the total assets in the Ethereum liquidity position.
     * @return The total value of assets in the Ethereum liquidity position.
     */
    function getTotalEthLPAssets() internal view returns (uint256) {
        (uint256 wstethAmount, uint256 wethAmount) = (0, 0);
        if (ethLPState.liquidity > 0) {
            int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
            (wstethAmount, wethAmount) = LiquidityAmounts
                .getAmountsForLiquidityByTick(
                    tick,
                    ethLPState.lowerTick,
                    ethLPState.upperTick,
                    ethLPState.liquidity
                );
        }

        return
            ethLPState.unAllocatedBalance +
            (IERC20(arb).balanceOf(address(this)) *
                ethSwapProxy.getPriceOf(arb, usd)) /
            1e18 +
            ((IERC20(wstEth).balanceOf(address(this)) + wstethAmount) *
                _getWstEthPrice()) /
            1e18 +
            ((IERC20(weth).balanceOf(address(this)) + wethAmount) *
                ethSwapProxy.getPriceOf(weth, usd)) /
            1e18;
    }

    /**
     * @dev Swaps an amount of one token for another in the Ethereum liquidity position.
     * @param tokenIn Address of the input token.
     * @param amountIn Amount of input token to swap.
     * @param tokenOut Address of the output token.
     * @return amountOut The amount of output token received after the swap.
     */
    function _ethLPSwapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(ethSwapProxy), amountIn);
        return ethSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    /**
     * @dev Retrieves the price of wrapped Ethereum (WstETH) in Ethereum.
     * @return The price of WstETH in Ethereum.
     */
    function _getWstEthPrice() private view returns (uint256) {
        return
            (ethSwapProxy.getPriceOf(wstEth, weth) *
                ethSwapProxy.getPriceOf(weth, usd)) / 1e18;
    }

    /**
     * @dev Decreases liquidity in the Ethereum liquidity position.
     * @param liquidity Amount of liquidity to decrease.
     * @return amount0 The amounts of tokens received after the decrease in liquidity.
     * @return amount1 The amounts of tokens received after the decrease in liquidity.
     */
    function _decreaseEthLPLiquidity(
        uint128 liquidity
    ) private returns (uint256 amount0, uint256 amount1) {
        ethLPProvider.decreaseLiquidityCurrentRange(
            ethLPState.tokenId,
            liquidity
        );

        (amount0, amount1) = ethLPProvider.collectAllFees(ethLPState.tokenId);

        ethLPState.liquidity -= liquidity;

        return (amount0, amount1);
    }

    /**
     * @dev Converts an amount of tokens to pool liquidity.
     * @param amount Amount of tokens to convert.
     * @return The corresponding pool liquidity amount.
     */
    function _amountToPoolLiquidity(
        uint256 amount
    ) private view returns (uint128) {
        int24 tick = ethSwapProxy.getPoolCurrentTickOf(wstEth, weth);
        (uint256 wstethAmount, uint256 wethAmount) = LiquidityAmounts
            .getAmountsForLiquidityByTick(
                tick,
                ethLPState.lowerTick,
                ethLPState.upperTick,
                ethLPState.liquidity
            );
        uint256 liquidAsset = (wstethAmount *
            _getWstEthPrice() +
            wethAmount *
            ethSwapProxy.getPriceOf(weth, usd)) / 1e18;

        return uint128((amount * ethLPState.liquidity) / liquidAsset);
    }

    /**
     * @dev Rebalances assets in the Ethereum liquidity position.
     * @param ratio Ratio used for rebalancing.
     * @param decimals Decimals used for ratio.
     */
    function _rebalanceEthLPAssets(uint16 ratio, uint8 decimals) private {
        uint256 amountToSwap = ethLPState.unAllocatedBalance;
        ethLPState.unAllocatedBalance = 0;

        _ethLPSwapTo(usd, amountToSwap, weth);

        uint256 ethAmountToSwap = (IERC20(weth).balanceOf(address(this)) *
            ratio) / 10 ** decimals;
        _ethLPSwapTo(weth, ethAmountToSwap, wstEth);
    }

    /**
     * @dev Retrieves the current state of the Ethereum liquidity position.
     * @return The current state of the Ethereum liquidity position.
     */
    function getEthLPState() external view returns (EthLPState memory) {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        return ethLPState;
    }
}
