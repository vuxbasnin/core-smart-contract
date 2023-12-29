// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IGetPriceProxy {
    function getEthPrice() external view returns (uint256 price);
    function getWstEthPrice() external view returns (uint256 price);
    function getEthWstEthPrice() external view returns (uint256 price);
}
