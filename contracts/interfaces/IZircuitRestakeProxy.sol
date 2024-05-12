// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IZircuitRestakeProxy {
    function depositFor(address token, address to, uint256 amount) external;
    function balanceOf(address token, address owner) external returns(uint256);
}