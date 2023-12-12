// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPriceFeedProxy.sol";

contract ChainLinkPriceFeedOracle is IPriceFeedProxy {
    AggregatorV3Interface internal priceFeed;

    constructor(address priceFeedAddress) {
        priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    // Get the latest ETH price
    function getLastEthPrice() external view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer);
    }
}
