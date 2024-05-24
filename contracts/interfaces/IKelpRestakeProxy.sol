// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IKelpRestakeProxy {
    function swapToRsETH(uint256 wstETHAmount, string calldata referralId) external payable;
    function depositETH(uint256 minRSETHAmountExpected, string calldata referralId) external payable;
}