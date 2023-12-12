// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ISwapProxy {
    function swap(uint256 amount) external returns (uint256) ;
}
