// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IAevo {
    function depositToAppChain(
        address receiver,
        address asset,
        uint256 amount,
        uint256 msgGasLimit,
        address connector,
        bytes memory data
    ) external payable;
}
