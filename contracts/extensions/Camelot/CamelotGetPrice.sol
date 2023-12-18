// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../lib/BaseGetPrice.sol";

contract CamelotGetPrice is BaseGetPrice {
    constructor(address _usdcEthPoolAddress, address _ethWstEthPoolAddress) BaseGetPrice(_usdcEthPoolAddress, _ethWstEthPoolAddress){}
}