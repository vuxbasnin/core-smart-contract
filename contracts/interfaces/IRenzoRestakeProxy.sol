// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRenzoRestakeProxy {
    function deposit(address collateralToken,uint256 amount) external;
}