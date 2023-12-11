// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPriceFeedProxy.sol";

contract PriceFeedOracle {
    IPriceFeedProxy internal priceFeed;

    constructor(address priceFeedProxyAddress) {
        priceFeed = IPriceFeedProxy(priceFeedProxyAddress);
    }

    // Get the latest ETH price
    function getLatestEthereumPrice() external view returns (uint256) {
        return priceFeed.getLastEthPrice();
    }
}
