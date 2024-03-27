// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../lib/ShareMath.sol";
import "../../../lib/LiquidityAmounts.sol";
import "../../../interfaces/IVenderLiquidityProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "../../../interfaces/IRewardVendor.sol";
import "../../../interfaces/IERC721Receiver.sol";
import "../structs/DeltaNeutralStruct.sol";
import "hardhat/console.sol";

contract RockOynxEthStakeLendStrategy is
    RockOnyxAccessControl,
    ReentrancyGuard
{
    using LiquidityAmounts for uint256;
    ISwapProxy internal ethSwapProxy;

    address usd;
    address weth;
    address wstEth;

    EthStakeLendState ethStakeLendState;
    uint8 slippage;

    /************************************************
     *  EVENTS
     ***********************************************/
    event PositionOpened(uint256 inputUsdAmount, uint256 ethPrice, uint256 wethAmount, uint256 wstEthAmount);
    event PositionClosed(uint256 usdAmount, uint256 wstEthEthPrice, uint256 ethToUsdPrice, uint256 ethAmountFomUsd, uint256 wstEthAmountFomEth, uint256 convertedWEthAmount, uint256 convertedUsdAmount);

    constructor() {
        ethStakeLendState = EthStakeLendState(0, 0);
    }

    function ethStakeLend_Initialize(
        address _swapAddress,
        address _usd,
        address _weth,
        address _wstEth
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        ethSwapProxy = ISwapProxy(_swapAddress);
        usd = _usd;
        weth = _weth;
        wstEth = _wstEth;
        slippage = 50;
    }

    // slippage decimals: 4 ---- ex: 50 mean 0.5%
    function setSlippage(uint8 _slippage) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        slippage = _slippage;
    }

    function openPosition(uint256 ethAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        uint256 ethPrice = _getEthPrice();
        uint256 usdcAmount = ethAmount * ethPrice * (1e4 + slippage) / 1e22;
        require(usdcAmount <= ethStakeLendState.unAllocatedBalance, "INVALID_REACH_UNALLOCATED_BALANCE");
        ethStakeLendState.unAllocatedBalance -= usdcAmount;
        
        uint256 usedUsdAmount = _ethStakeLendSwapToWithOutput(usd, ethAmount, weth, usdcAmount);
        ethStakeLendState.unAllocatedBalance += (usdcAmount - usedUsdAmount);
        uint256 wstEthAmount = _ethStakeLendSwapTo(weth, ethAmount, wstEth);
        emit PositionOpened(usdcAmount, ethPrice, ethAmount, wstEthAmount);
    }

    function closePosition(uint256 ethAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        uint256 ethPrice = _getEthPrice();
        uint256 usdAmount = ethAmount * ethPrice;

        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        uint256 wstEthAmount = ethAmount * wstEthEthPrice * (1e4 + slippage) / 1e22;

        require(wstEthAmount <= IERC20(wstEth).balanceOf(address(this)), "INVALID_REACH_WSTETH_AMOUNT");
        
        _ethStakeLendSwapToWithOutput(wstEth, ethAmount, weth, wstEthAmount);
    
        uint256 receivedUsdAmount = _ethStakeLendSwapTo(weth, ethAmount, usd);
        ethStakeLendState.unAllocatedBalance += receivedUsdAmount;

        console.log("1.wstEthEthPrice %s", wstEthEthPrice);
        console.log("2.ethToUsdPrice %s", _getEthPrice());
        console.log("3.ethAmount %s", ethAmount);
        console.log("4.wstEthAmount %s, balance %s", wstEthAmount, IERC20(wstEth).balanceOf(address(this)));
        console.log("5.receivedUsdAmount %s", receivedUsdAmount);
        
        emit PositionClosed(usdAmount, wstEthEthPrice, ethPrice, ethAmount, wstEthAmount, ethAmount, receivedUsdAmount);
    }

    /**
     * @dev Retrieves the current state of the Ethereum liquidity position.
     * @return The current state of the Ethereum liquidity position.
     */
    function getEthStakeLendState() external view returns (EthStakeLendState memory) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return ethStakeLendState;
    }

    /**
     * @dev Deposit an amount into the Ethereum Stake & Lend strategy.
     * @param amount The amount to deposit into the Ethereum Stake & Lend strategy.
     */
    function depositToEthStakeLendStrategy(uint256 amount) internal {
        ethStakeLendState.unAllocatedBalance += amount;
        ethStakeLendState.totalBalance += amount;
    }

    function syncEthStakeLendBalance() internal {
        ethStakeLendState.totalBalance = 
            ethStakeLendState.unAllocatedBalance + IERC20(wstEth).balanceOf(address(this)) * _getWstEthPrice() / 1e18;
    }

    function handleFundsFromEthStakeLend(uint256 amount) internal returns (uint256) {
        uint256 unAllocatedBalance = ethStakeLendState.unAllocatedBalance;
        if(ethStakeLendState.unAllocatedBalance >= amount){
            ethStakeLendState.unAllocatedBalance -= amount;
            ethStakeLendState.totalBalance -= amount;
            return amount;
        }

        ethStakeLendState.unAllocatedBalance = 0;
        uint256 amountToAcquire = amount - unAllocatedBalance;
        uint256 wstEthAmount = amountToAcquire * 1e18 / _getWstEthPrice();
        uint256 wethAmount = _ethStakeLendSwapTo(wstEth, wstEthAmount, weth);
        uint256 usdcAmount = _ethStakeLendSwapTo(weth, wethAmount, usd);
        ethStakeLendState.totalBalance -= (unAllocatedBalance + usdcAmount);
        return unAllocatedBalance + usdcAmount;
    }

    /**
     * @dev Calculates the total assets in the Ethereum liquidity position.
     * @return The total value of assets in the Ethereum liquidity position.
     */
    function getTotalEthStakeLendAssets() internal view returns (uint256) { 
        return ethStakeLendState.totalBalance;
    }

    /**
     * @dev Retrieves the price of Ethereum in USD.
     * @return The price of Ethereum in USD.
     */
    function _getEthPrice() private view returns (uint256) {
        return ethSwapProxy.getPriceOf(usd, weth, 6, 18);
    }

    /**
     * @dev Retrieves the price of wrapped Ethereum (WstETH) in Ethereum.
     * @return The price of WstETH in Ethereum.
     */
    function _getWstEthPrice() private view returns (uint256) {
        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        return wstEthEthPrice * _getEthPrice() / 1e18;
    }

    /**
     * @dev Retrieves the unallocated balance in the Ethereum Stake & Lend strategy.
     * @return The unallocated balance in the Ethereum Stake & Lend strategy.
     */
    function getUnAllocatedBalance() external view returns (uint256) {
        return ethStakeLendState.unAllocatedBalance;
    }

    /**
     * @dev Swaps an amount of one token for another in the Ethereum liquidity position.
     * @param tokenIn Address of the input token.
     * @param amountIn Amount of input token to swap.
     * @param tokenOut Address of the output token.
     * @return amountOut The amount of output token received after the swap.
     */
    function _ethStakeLendSwapTo(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(ethSwapProxy), amountIn);
        return ethSwapProxy.swapTo(address(this), tokenIn, amountIn, tokenOut);
    }

    function _ethStakeLendSwapToWithOutput(
        address tokenIn,
        uint256 amountOut,
        address tokenOut,
        uint256 amountInMaximum
    ) private returns (uint256 amountIn) {
        IERC20(tokenIn).approve(address(ethSwapProxy), amountInMaximum);
        return ethSwapProxy.swapToWithOutput(address(this), tokenIn, amountOut, tokenOut, amountInMaximum);
    }
}
