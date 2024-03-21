// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IAevo.sol";

contract MockAEVO is IAevo {
    // Event for logging deposits
    event DepositToAppChain(
        address indexed receiver,
        uint256 amount,
        uint256 msgGasLimit,
        address connector
    );

    function depositToAppChain(
        address receiver,
        uint256 amount,
        uint256 msgGasLimit,
        address connector
    ) external payable override {
        emit DepositToAppChain(receiver, amount, msgGasLimit, connector);
    }

    function depositToAppChain(
        address receiver,
        address asset,
        uint256 amount,
        uint256 msgGasLimit,
        address connector,
        bytes memory data
    ) external payable override {
        emit DepositToAppChain(receiver, amount, msgGasLimit, connector);
    }
}
