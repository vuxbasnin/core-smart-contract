// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../../interfaces/AggregatorV3Interface.sol";

contract UsdceUsdcPriceFeedOracle is AggregatorV3Interface{
    address owner;
    uint8 tokenDecimals;
    uint256 lastestPrice;

    constructor(uint256 _price, uint8 _decimals){
        owner = msg.sender;
        lastestPrice = _price;
        tokenDecimals = _decimals;
    }

    event PriceUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);

    function setLatestPrice(uint256 _price) external {
        require(msg.sender == owner, "INVALID_ADMIN");

        uint256 oldPrice = lastestPrice;
        lastestPrice = _price;

        emit PriceUpdated(oldPrice, lastestPrice, block.timestamp);
    }

    function latestRoundData() external view returns (uint80 roundId, uint256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (uint80(block.timestamp), lastestPrice, block.timestamp, block.timestamp, uint80(block.timestamp));
    }

    function decimals() external view returns (uint8){
        return tokenDecimals;
    }
}
