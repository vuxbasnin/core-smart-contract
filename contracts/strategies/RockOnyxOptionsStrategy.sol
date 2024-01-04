// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../interfaces/IOptionsVendorProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RockOnyxOptionStrategy is RockOnyxAccessControl, ReentrancyGuard {
    address internal vendorAddress;
    address internal optionsAssetAddress;
    address internal vaultAssetAddress;
    address internal optionsReceiver;
    IOptionsVendorProxy internal optionsVendor;
    uint256 internal allocatedBalance;
    uint256 internal unAllocatedBalance;
    ISwapProxy private swapProxy;

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
        uint256 oldBalance,
        uint256 newBalance
    );

    constructor(
        address _vendorAddress,
        address _optionsReceiver,
        address _optionsAssetAddress,
        address _vaultAssetAddress,
        address _swapAddress
    ) {
        vendorAddress = _vendorAddress;
        optionsVendor = IOptionsVendorProxy(vendorAddress);
        allocatedBalance = 0;
        unAllocatedBalance = 0;
        optionsReceiver = _optionsReceiver;
        optionsAssetAddress = _optionsAssetAddress;
        vaultAssetAddress = _vaultAssetAddress;
        swapProxy = ISwapProxy(_swapAddress);
    }

    function depositToOptionsStrategy(uint256 amountIn) internal {
        // Ensure the contract has enough allowance to perform the swap
        IERC20(vaultAssetAddress).approve(address(swapProxy), amountIn);
        console.log("swapProxy %s", address(swapProxy));

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            vaultAssetAddress,
            amountIn,
            optionsAssetAddress
        );

        console.log("Swap to USDC.e %s", swappedAmount);

        uint256 swappedAmount2 = IERC20(vaultAssetAddress).balanceOf(
            address(this)
        );
        console.log("vaultAssetAddress %s", swappedAmount2);

        // After the swap, the contract should hold the swapped tokens in optionsAssetAddress
        // Update the unAllocatedBalance with the swapped amount
        uint256 swappedAmount1 = IERC20(optionsAssetAddress).balanceOf(
            address(this)
        );
        console.log("swappedAmount1 %s", swappedAmount1);

        unAllocatedBalance += swappedAmount;

        console.log(
            "Deposited to options strategy and swapped, unAllocatedBalance = %s",
            unAllocatedBalance
        );
    }

    function withdrawFromOptionsStrategy(uint256 amount) internal {
        unAllocatedBalance -= amount;
        console.log(
            "Handle withdrawFromOptionsStrategy, unAllocatedBalance = %s",
            unAllocatedBalance
        );
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor(uint256 amount) external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        console.log("unAllocatedBalance %s", unAllocatedBalance);
        require(amount <= unAllocatedBalance, "INVALID_DEPOSIT_VENDOR_AMOUNT");

        console.log("Deposit to vendor in strategy %d", amount);
        console.log(
            "optionsAssetAddress %d, optionsVendor %s",
            address(optionsAssetAddress),
            address(optionsVendor)
        );

        IERC20(optionsAssetAddress).approve(address(optionsVendor), amount);
        uint256 allowedamt = IERC20(optionsAssetAddress).allowance(
            address(this),
            address(optionsVendor)
        );
        console.log("Allowance amount for AevoOptions %s", allowedamt);

        optionsVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            amount
        );
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

        emit OptionsBalanceChanged(oldBalance, unAllocatedBalance);
    }

    function closeOptionsRound(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 oldAllocatedBalance = allocatedBalance;

        allocatedBalance = balance;

        // Emitting an event to log the change in allocated balance
        emit OptionsBalanceChanged(
            oldAllocatedBalance,
            allocatedBalance
        );
    }

    function totalAllocatedAmount() internal view returns (uint256) {
        return allocatedBalance + unAllocatedBalance;
    }
}
