// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


import "../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../interfaces/IOptionsVendorProxy.sol";

contract RockOnyxOptionStrategy is RockOnyxAccessControl, ReentrancyGuard {
    address internal vendorAddress;
    address internal optionsReceiver;
    IOptionsVendorProxy internal optionsVendor;
    uint256 internal allocatedBalance;
    uint256 internal unAllocatedBalance;

    /************************************************
     *  EVENTS
     ***********************************************/
    event OptionsVendorDeposited(
        address connector,
        address receiver,
        uint256 depositAmount
    );

    event OptionsVendorWithdrawed(uint256 amount);

    event OptionsBalanceChanged(
        uint256 changedAmount,
        uint256 oldBalance,
        uint256 newBalance
    );

    constructor(address _vendorAddress, address _optionsReceiver) {
        vendorAddress = _vendorAddress;
        optionsVendor = IOptionsVendorProxy(vendorAddress);
        allocatedBalance = 0;
        unAllocatedBalance = 0;
        optionsReceiver = _optionsReceiver;
    }

    function depositToOptionsStrategy(uint256 amount) internal {
        unAllocatedBalance += amount;
        console.log("Handle depositToOptionsStrategy, unAllocatedBalance = %s", unAllocatedBalance);
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(amount <= unAllocatedBalance, "INVALID_DEPOSIT_VENDOR_AMOUNT");

        optionsVendor.depositToVendor(optionsReceiver, amount, vendorAddress);
        unAllocatedBalance -= amount;
        allocatedBalance += amount;

        emit OptionsVendorDeposited(vendorAddress, optionsReceiver, amount);
    }

    function withdrawFromVendor(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        emit OptionsVendorWithdrawed(amount);
    }

    function handlePostWithdrawalFromVendor(
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "INVALID_WITHDRAW_AMOUNT");
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 oldBalance = unAllocatedBalance;
        unAllocatedBalance += amount;
        allocatedBalance -= amount;

        emit OptionsBalanceChanged(amount, oldBalance, unAllocatedBalance);
    }

    function totalAllocatedAmount() private view returns (uint256) {
        return allocatedBalance + unAllocatedBalance;
    }
}
