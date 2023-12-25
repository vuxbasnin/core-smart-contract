// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IAevo {
    
    function depositToAppChain(
        address receiver,
        uint256 amount,
        uint256 msgGasLimit,
        address connector
    ) external payable;

}
