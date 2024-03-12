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

    /**
     * @dev Deposit an amount into the options strategy.
     * @param amountIn The amount to deposit into the options strategy.
     */
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

    /**
     * @dev Handles withdrawal from the vendor.
     * @param amount The amount to be withdrawn.
     */
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
    }

    /**
     * @dev Closes the current options round, adjusting balances based on settled profits and losses.
     */
    function closeOptionsRound() internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if (optionsState.unsettledProfit > 0) {
            optionsState.allocatedUsdceBalance += optionsState.unsettledProfit;
            optionsState.unsettledProfit = 0;    
        }
        
        if (optionsState.unsettledLoss > 0) {
            optionsState.allocatedUsdceBalance -= optionsState.unsettledLoss;
            optionsState.unsettledLoss = 0;
        }
    }

    /**
     * @dev Updates profit and loss balances from the vendor.
     * @param balance The updated balance from the vendor.
     */
    function updateProfitFromVender(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsState.unsettledProfit = balance > optionsState.allocatedUsdceBalance ? balance - optionsState.allocatedUsdceBalance : 0;
        optionsState.unsettledLoss = balance < optionsState.allocatedUsdceBalance ? optionsState.allocatedUsdceBalance - balance : 0;
    }

    /**
     * @dev Calculates the total options amount based on allocated and unallocated balances.
     * @return The total options amount.
     */
    function getTotalOptionsAmount() internal view returns (uint256) {
        return 
            optionsState.unAllocatedUsdcBalance +
            (optionsState.allocatedUsdceBalance * swapProxy.getPriceOf(optionsAssetAddress, vaultAssetAddress, 6, 6)) / 1e6;
    }
}
