// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IAevo {
    // function getMinFees(address connector, uint256 msgGasLimit) external;

    function depositToAppChain(
        address receiver,
        uint256 amount,
        uint256 msgGasLimit,
        address connector
    ) external payable;

    function depositToAppChain(
        address receiver,
        address asset,
        uint256 amount,
        uint256 msgGasLimit,
        address connector,
        bytes memory data
    ) external payable;
}
