// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IAevo.sol";
import "../../interfaces/IOptionsVendorProxy.sol";

contract AevoOptions is IOptionsVendorProxy {
    IAevo internal AEVO;
    uint256 internal gasLimit;

    constructor(address aevoAddress) {
        AEVO = IAevo(aevoAddress);
        gasLimit = 1000000;
    }

    function depositToVendor(
        address receiver,
        uint256 amount,
        address connector
    ) external {
        require(amount > 0, "INVALID_DEPOSIT_AMOUNT");

        AEVO.depositToAppChain(receiver, amount, gasLimit, connector);

    }

    function withdrawFromVendor(uint256 amount) external {
        // Implementation of withdrawFromVendor
    }
}
