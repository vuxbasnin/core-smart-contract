// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/AggregatorV3Interface.sol";
import "../../interfaces/IPriceConsumerProxy.sol";
import "hardhat/console.sol";

contract PriceConsumer is IPriceConsumerProxy {
    mapping(address => mapping(address => AggregatorV3Interface)) private priceFeeds;
    address owner;

    constructor(
        address _admin,
        address[] memory _token1PriceFeeds,
        address[] memory _token2PriceFeeds,
        address[] memory _priceFeeds)
    {
        owner = _admin;

        for (uint8 i = 0; i < _priceFeeds.length; i++) {
            priceFeeds[_token1PriceFeeds[i]][_token2PriceFeeds[i]] = AggregatorV3Interface(_priceFeeds[i]);
        }
    }

    function getPriceOf(address token0, address token1) external view returns (uint256 price){
        AggregatorV3Interface priceFeed = priceFeeds[token0][token1];
        address slot0 = token0;

        if(address(priceFeed) == address(0)){
            priceFeed = priceFeeds[token1][token0];
            slot0 = token1;
        }

        (, price, , ,) = priceFeed.latestRoundData();

         if(slot0 != token0){
            return 10 ** (ERC20(token1).decimals() * 2) / (price * 10 ** ERC20(token1).decimals() / 10 ** priceFeed.decimals());
        }

        return price * 10 ** ERC20(token1).decimals() / 10 ** priceFeed.decimals();
    }

    function updatePriceFeed(address token0, address token1, address priceFeed) external {
        require(msg.sender == owner, "INVALID_ADMIN");

        priceFeeds[token0][token1] = AggregatorV3Interface(priceFeed);
    }

    function getPriceFeed(address token0, address token1) external view returns (address){
        require(msg.sender == owner, "INVALID_ADMIN");

        return address(priceFeeds[token0][token1]);
    }
}
