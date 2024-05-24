// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRenzoRestakeProxy {
    function depositETH() external payable ;
    function depositETH(uint256 minOut, uint256 deadline) external payable;
}