// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "../TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RockOnyxSwap {
    constructor(address _swapRouterAddress) {}

    function swapTo(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external returns (uint256) {
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        TransferHelper.safeTransfer(tokenOut, recipient, amountIn);
        return amountIn;
    }

    function getPriceOf(
        address token0,
        address token1,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) external view returns (uint256 price) {
        return 1;
    }
}
