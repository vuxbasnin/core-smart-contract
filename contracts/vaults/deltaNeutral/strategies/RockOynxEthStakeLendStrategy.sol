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

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor() {
        ethStakeLendState = EthStakeLendState(0);
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
    }

    /**
     * @dev Deposit an amount into the Ethereum Stake & Lend strategy.
     * @param amount The amount to deposit into the Ethereum Stake & Lend strategy.
     */
    function depositToEthStakeLendStrategy(uint256 amount) internal {
        ethStakeLendState.unAllocatedBalance += amount;
    }

    function openPosition(uint256 usdAmount) internal returns(uint256 returnAmount, uint256 price){
        require(usdAmount <= ethStakeLendState.unAllocatedBalance, "INVALID_REACH_UNALLOCATED_BALANCE");

        price = _getEthPrice();
        ethStakeLendState.unAllocatedBalance -= usdAmount;
        uint256 wethAmount = _ethStakeLendSwapTo(usd, usdAmount, weth);
        _ethStakeLendSwapTo(weth, wethAmount, wstEth);

        return (wethAmount, price);
    }

    function closePosition(uint256 ethAmount) internal returns(uint256 returnAmount, uint256 price){
        uint256 wstEthEthPrice = ethSwapProxy.getPriceOf(wstEth, weth, 18, 18);
        uint256 wstEthAmount = ethAmount * wstEthEthPrice;

        require(wstEthAmount <= IERC20(wstEth).balanceOf(address(this)), "INVALID_REACH_WSTETH_AMOUNT");

        price = _getEthPrice();
        uint256 wethAmount = _ethStakeLendSwapTo(wstEth, wstEthAmount, weth);
        uint256 usdAmount = _ethStakeLendSwapTo(weth, wethAmount, usd);
        ethStakeLendState.unAllocatedBalance += usdAmount;

        return (usdAmount, price);
    }

    function acquireWithdrawalFundsEthStakeLend(uint256 amount) internal returns (uint256){
        uint256 unAllocatedBalance = ethStakeLendState.unAllocatedBalance;
        if(ethStakeLendState.unAllocatedBalance >= amount){
            ethStakeLendState.unAllocatedBalance -= amount;
            return amount;
        }

        ethStakeLendState.unAllocatedBalance = 0;
        uint256 amountToAcquire = amount - unAllocatedBalance;
        uint256 wstEthAmount = amountToAcquire / _getWstEthPrice();
        uint256 wethAmount = _ethStakeLendSwapTo(wstEth, wstEthAmount, weth);
        return unAllocatedBalance + _ethStakeLendSwapTo(weth, wethAmount, usd);
    }

    /**
     * @dev Calculates the total assets in the Ethereum liquidity position.
     * @return The total value of assets in the Ethereum liquidity position.
     */
    function getTotalEthStakeLendAssets() internal view returns (uint256) { 
        return 
            ethStakeLendState.unAllocatedBalance +
            IERC20(wstEth).balanceOf(address(this)) * _getWstEthPrice() / 1e18;
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
     * @dev Retrieves the current state of the Ethereum liquidity position.
     * @return The current state of the Ethereum liquidity position.
     */
    function getEthStakeLendState() external view returns (EthStakeLendState memory) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return ethStakeLendState;
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
}
