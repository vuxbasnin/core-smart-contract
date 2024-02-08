// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../interfaces/IOptionsVendorProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../structs/RockOnyxStructs.sol";

contract RockOnyxOptionStrategy is RockOnyxAccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    event OptionsBalanceChanged(uint256 oldBalance, uint256 newBlanace);

    constructor() {
        optionsState = OptionsStrategyState(0, 0, 0, 0);
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

        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, msg.sender);
        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, optionsReceiver);
    }

    function depositToOptionsStrategy(uint256 amountIn) internal {
        optionsState.unAllocatedUsdcBalance += amountIn;
    }

    /**
     * @notice Acquires withdrawal funds in USDC options
     * @param withdrawUsdOptionsAmount The requested withdrawal amount in USDC
     */
    function acquireWithdrawalFundsUsdOptions(uint256 withdrawUsdOptionsAmount) internal returns (uint256) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if(optionsState.unAllocatedUsdcBalance > withdrawUsdOptionsAmount){
            optionsState.unAllocatedUsdcBalance -= withdrawUsdOptionsAmount;
            return withdrawUsdOptionsAmount;    
        }

        uint256 unAllocatedUsdcBalance = optionsState.unAllocatedUsdcBalance;
        optionsState.unAllocatedUsdcBalance = 0;
        return unAllocatedUsdcBalance;
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor() external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC20(vaultAssetAddress).approve(address(swapProxy), optionsState.unAllocatedUsdcBalance);

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            vaultAssetAddress,
            optionsState.unAllocatedUsdcBalance,
            optionsAssetAddress
        );

        optionsState.unAllocatedUsdcBalance = 0;

        IERC20(optionsAssetAddress).approve(address(optionsVendor), swappedAmount);

        optionsVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            swappedAmount            
        );

        emit OptionsVendorDeposited(address(optionsVendor), optionsReceiver, swappedAmount);

        optionsState.allocatedUsdceBalance += swappedAmount;
    }

    function handlePostWithdrawalFromVendor(
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "INVALID_WITHDRAW_AMOUNT");
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        IERC20(optionsAssetAddress).safeTransferFrom(msg.sender, address(this), amount);

        emit OptionsBalanceChanged(optionsState.unAllocatedUsdcBalance, optionsState.unAllocatedUsdcBalance + amount);

        IERC20(optionsAssetAddress).approve(address(swapProxy), amount);

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            optionsAssetAddress,
            amount,
            vaultAssetAddress
        );

        optionsState.unAllocatedUsdcBalance += swappedAmount;
        optionsState.allocatedUsdceBalance -= amount;

        console.log("amount %s", amount);
        console.log("optionsState.unAllocatedBalance %s", optionsState.unAllocatedUsdcBalance);
        console.log("optionsState.allocatedBalance %s", optionsState.allocatedUsdceBalance);
    }

    function closeOptionsRound() internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        console.log("optionsState.unsettledProfit %s", optionsState.unsettledProfit);
        console.log("optionsState.unsettledLoss %s", optionsState.unsettledLoss);
        if (optionsState.unsettledProfit > 0) {
            optionsState.allocatedUsdceBalance += optionsState.unsettledProfit;    
        }
        
        if (optionsState.unsettledLoss > 0) {
            optionsState.allocatedUsdceBalance -= optionsState.unsettledLoss;
        }
        console.log("optionsState.allocatedBalance %s", optionsState.allocatedUsdceBalance);
        console.log("optionsState.unallocatedBalance %s", optionsState.unAllocatedUsdcBalance);
    }

    function updateProfitFromVender(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsState.unsettledProfit = balance > optionsState.allocatedUsdceBalance ? balance - optionsState.allocatedUsdceBalance : 0;
        optionsState.unsettledLoss = balance < optionsState.allocatedUsdceBalance ? optionsState.allocatedUsdceBalance - balance : 0;
    }

    function getTotalOptionsAmount() internal view returns (uint256) {
        // console.log('getTotalOptionsAmount ', 
        //     optionsState.unAllocatedUsdcBalance +
        //    (optionsState.allocatedUsdceBalance * swapProxy.getPriceOf(optionsAssetAddress, vaultAssetAddress, 6, 6)) / 1e6);
        return 
            optionsState.unAllocatedUsdcBalance +
            (optionsState.allocatedUsdceBalance * swapProxy.getPriceOf(optionsAssetAddress, vaultAssetAddress, 6, 6)) / 1e6;
    }
}
