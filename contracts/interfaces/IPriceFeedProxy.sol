// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPriceFeedProxy {
    function getLastEthPrice() external view returns(uint256);
}