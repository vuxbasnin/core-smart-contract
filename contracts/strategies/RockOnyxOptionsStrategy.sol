// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../interfaces/IOptionsVendorProxy.sol";

contract RockOnyxOptionStrategy is RockOnyxAccessControl, ReentrancyGuard {
    address internal vendorAddress;
    IOptionsVendorProxy internal optionsVendor;
    uint256 internal balance;

    /************************************************
     *  EVENTS
     ***********************************************/
    event OptionsVendorDeposited(
        address connector,
        address depositor,
        address receiver,
        uint256 depositAmount
    );

    event OptionsVendorWithdrawed(
        uint256 amount
    );

    event OptionsBalanceChanged(
        uint256 changedAmount,
        uint256 oldBalance,
        uint256 newBalance
    );

    constructor(address _vendorAddress) {
        vendorAddress = _vendorAddress;
        optionsVendor = IOptionsVendorProxy(vendorAddress);
        balance = 0;
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor(
        address receiver,
        uint256 amount
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsVendor.depositToVendor(receiver, amount, vendorAddress);
        // balance -= amount;

        emit OptionsVendorDeposited(vendorAddress, receiver, receiver, amount);
    }

    function withdrawFromVendor(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        emit OptionsVendorWithdrawed(amount);
    }

    function handlePostWithdrawalFromVendor(uint256 amount) external nonReentrant {
        require(amount > 0, "INVALID_WITHDRAW_AMOUNT");
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 oldBalance = balance;
        balance += amount;

        emit OptionsBalanceChanged(amount, oldBalance, balance);
    }
}
