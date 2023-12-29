// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../lib/BaseSwap.sol";

contract CamelotSwap is BaseSwap {
    constructor(ISwapRouter _swapRouter, uint24 _fee) BaseSwap(_swapRouter, _fee){
    }
}