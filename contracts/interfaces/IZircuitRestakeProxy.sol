// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IZircuitRestakeProxy {
    function depositFor(address _token, address _for, uint256 _amount) external;
}