// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IAevo.sol";
import "../../interfaces/IOptionsVendorProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../RockOnyxAccessControl.sol";
// import "hardhat/console.sol";
import "../../lib/BaseProxy.sol";

contract AevoOptions is IOptionsVendorProxy, BaseProxy {
    IAevo internal AEVO;
    uint256 internal gasLimit;
    address public immutable asset;
    address internal connector;

    constructor(address _asset, address aevoAddress, address _connector) {
        AEVO = IAevo(aevoAddress);
        connector = _connector;
        gasLimit = 1000000;
        asset = _asset;
    }

    function depositToVendor(
        address receiver,
        uint256 amount
    ) external payable nonReentrant {
        require(amount > 0, "INVALID_DEPOSIT_AMOUNT");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        IERC20(asset).approve(address(AEVO), amount);

        AEVO.depositToAppChain{value: msg.value}(
            receiver,
            amount,
            gasLimit,
            connector
        );
    }
}
