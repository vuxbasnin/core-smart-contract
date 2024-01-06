// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../interfaces/IOptionsVendorProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../structs/RockOnyxStructs.sol";

contract RockOnyxOptionStrategy is RockOnyxAccessControl, ReentrancyGuard {
    address internal optionsAssetAddress;
    address internal vaultAssetAddress;
    address internal optionsReceiver;
    IOptionsVendorProxy internal optionsVendor;
    OptionsStrategyState internal optionsState;
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

    event OptionsBalanceChanged(uint256 oldBalance, uint256 newBalance);

    constructor() {
        optionsState = OptionsStrategyState(0, 0);
    }

    function options_Initialize(
        address _vendorAddress,
        address _optionsReceiver,
        address _optionsAssetAddress,
        address _vaultAssetAddress,
        address _swapAddress
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsVendor = IOptionsVendorProxy(_vendorAddress);
        swapProxy = ISwapProxy(_swapAddress);
        optionsReceiver = _optionsReceiver;
        optionsAssetAddress = _optionsAssetAddress;
        vaultAssetAddress = _vaultAssetAddress;
    }

    function depositToOptionsStrategy(uint256 amountIn) internal {
        // Ensure the contract has enough allowance to perform the swap
        IERC20(vaultAssetAddress).approve(address(swapProxy), amountIn);

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            vaultAssetAddress,
            amountIn,
            optionsAssetAddress
        );

        optionsState.unAllocatedBalance += swappedAmount;
    }

    function withdrawFromOptionsStrategy(uint256 amount) internal {
        optionsState.unAllocatedBalance -= amount;
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor(uint256 amount) external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(
            amount <= optionsState.unAllocatedBalance,
            "INVALID_DEPOSIT_VENDOR_AMOUNT"
        );
        IERC20(optionsAssetAddress).approve(address(optionsVendor), amount);

        optionsVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            amount
        );
        optionsState.unAllocatedBalance -= amount;
        optionsState.allocatedBalance += amount;

        emit OptionsVendorDeposited(address(optionsVendor), optionsReceiver, amount);
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

        uint256 oldBalance = optionsState.unAllocatedBalance;
        optionsState.unAllocatedBalance += amount;
        optionsState.allocatedBalance -= amount;

        emit OptionsBalanceChanged(oldBalance, optionsState.unAllocatedBalance);
    }

    function closeOptionsRound(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 oldAllocatedBalance = optionsState.allocatedBalance;

        optionsState.allocatedBalance = balance;

        // Emitting an event to log the change in allocated balance
        emit OptionsBalanceChanged(
            oldAllocatedBalance,
            optionsState.allocatedBalance
        );
    }

    function getTotalOptionsAmount() internal view returns (uint256) {
        
        return
            ((optionsState.allocatedBalance + optionsState.unAllocatedBalance) *
                swapProxy.getPriceOf(
                    optionsAssetAddress,
                    vaultAssetAddress,
                    6,
                    6
                )) / 1e6;
    }
}
