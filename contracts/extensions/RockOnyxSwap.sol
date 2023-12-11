// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISwapProxy.sol";

contract RockOnyxSwap {
    ISwapProxy internal swapProxy;

    constructor(address swapHandlerAddress) {
        swapProxy = ISwapProxy(swapHandlerAddress);
    }

    function swap(uint256 amount) external returns (uint256) {
        return swapProxy.Swap(amount);
    }
}
