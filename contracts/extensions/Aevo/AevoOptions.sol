// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IAevo.sol";
import "../../interfaces/IOptionsVendorProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../RockOnyxAccessControl.sol";
import "hardhat/console.sol";

contract AevoOptions is
    IOptionsVendorProxy,
    ReentrancyGuard,
    RockOnyxAccessControl
{
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

    function topUpGasFees() public payable {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        console.log("sender %s, amount %s", msg.sender, msg.value);
    }

    function depositToVendor(
        address receiver,
        uint256 amount
    ) external payable nonReentrant {
        require(amount > 0, "INVALID_DEPOSIT_AMOUNT");
        console.log(
            "[AevoOptions] Depositing to vendor from %s, asset %s, amount %d",
            msg.sender,
            asset,
            amount
        );

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        console.log("[AevoOptions] transfered from %s", msg.sender);

        IERC20(asset).approve(address(AEVO), amount);
        console.log(
            "[AevoOptions] Approved transaction for %s balance %s, ETH %s",
            address(AEVO),
            IERC20(asset).balanceOf(address(this)),
            address(this).balance
        );

        // uint256 amountInWei = 0.001753 * 10**18;
        AEVO.depositToAppChain{value: msg.value}(
            receiver,
            amount,
            gasLimit,
            connector
        );

        console.log(
            "[AevoOptions] Balance of AevoOptions after depositToAppChain %s",
            address(this).balance
        );
    }

    function withdrawFromVendor(uint256 amount) external {
        // Implementation of withdrawFromVendor
    }
}
