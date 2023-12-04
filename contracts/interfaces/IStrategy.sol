// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
    function invest() external;
    function divest(uint256 amount) external;
    function rebalance() external;
}
