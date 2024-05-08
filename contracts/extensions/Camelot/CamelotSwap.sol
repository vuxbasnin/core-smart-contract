// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../lib/BaseSwap.sol";

contract CamelotSwap is BaseSwap {
    constructor(address _swapRouterAddress) BaseSwap(_swapRouterAddress) {}
}
