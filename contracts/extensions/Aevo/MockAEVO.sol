// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IAevo.sol";

contract MockAEVO is IAevo {
    // Event for logging deposits
    event DepositToAppChain(
        address indexed receiver,
        address asset,
        uint256 amount,
        uint256 msgGasLimit,
        address connector,
        bytes data
    );

    function depositToAppChain(
        address receiver,
        address asset,
        uint256 amount,
        uint256 msgGasLimit,
        address connector,
        bytes memory data
    ) external payable override {
        emit DepositToAppChain(receiver, asset, amount, msgGasLimit, connector, data);
    }
}
