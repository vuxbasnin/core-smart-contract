// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPriceConsumerProxy {
    function getPriceOf(address token0, address token1) external view returns (uint256 price);
    function updatePriceFeed(address token0, address token1, address priceFeed) external;
    function getPriceFeed(address token0, address token1) external view returns (address);
}
