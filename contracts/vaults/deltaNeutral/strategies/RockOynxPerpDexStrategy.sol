// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../interfaces/IAevo.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../interfaces/IOptionsVendorProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../structs/DeltaNeutralStruct.sol";

contract RockOynxPerpDexStrategy is RockOnyxAccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address internal optionsAssetAddress;
    address internal vaultAssetAddress;
    address internal optionsReceiver;
    IOptionsVendorProxy internal optionsVendor;
    PerpDexState internal perpDexState;
    ISwapProxy private swapProxy;

    /************************************************
     *  EVENTS
     ***********************************************/
    event PerpDexVendorDeposited(
        address connector,
        address receiver,
        uint256 depositAmount
    );

    event PerpDexBalanceChanged(uint256 oldBalance, uint256 newBlanace);

    constructor() {
        perpDexState = PerpDexState(0, 0, 0);
    }

    function perpDex_Initialize(
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
    function depositToPerpDexStrategy(uint256 amountIn) internal {
        perpDexState.unAllocatedBalance += amountIn;
    }

    /**
     * @notice Acquires withdrawal funds in USDC options
     * @param withdrawUsdPerpDexAmount The requested withdrawal amount in USDC
     */
    function acquireWithdrawalFundsUsdPerpDex(uint256 withdrawUsdPerpDexAmount) internal returns (uint256) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if(perpDexState.unAllocatedBalance > withdrawUsdPerpDexAmount){
            perpDexState.unAllocatedBalance -= withdrawUsdPerpDexAmount;
            return withdrawUsdPerpDexAmount;    
        }

        uint256 unAllocatedUsdcBalance = perpDexState.unAllocatedBalance;
        perpDexState.unAllocatedBalance = 0;
        return unAllocatedUsdcBalance;
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor() external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC20(vaultAssetAddress).approve(address(swapProxy), perpDexState.unAllocatedBalance);

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            vaultAssetAddress,
            perpDexState.unAllocatedBalance,
            optionsAssetAddress
        );

        perpDexState.unAllocatedBalance = 0;

        IERC20(optionsAssetAddress).approve(address(optionsVendor), swappedAmount);

        optionsVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            swappedAmount            
        );

        emit PerpDexVendorDeposited(address(optionsVendor), optionsReceiver, swappedAmount);

        perpDexState.unAllocatedBalance += swappedAmount;
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

        emit PerpDexBalanceChanged(perpDexState.unAllocatedBalance, perpDexState.unAllocatedBalance + amount);

        IERC20(optionsAssetAddress).approve(address(swapProxy), amount);

        // Perform the swap from vaultAsset to optionsAsset
        uint256 swappedAmount = swapProxy.swapTo(
            address(this),
            optionsAssetAddress,
            amount,
            vaultAssetAddress
        );

        perpDexState.unAllocatedBalance += swappedAmount;
        perpDexState.unAllocatedBalance -= amount;
    }

    /**
     * @dev Closes the current options round, adjusting balances based on settled profits and losses.
     */
    function closePerpDexRound() internal {
        
        if (perpDexState.unsettledProfit > 0) {
            perpDexState.unAllocatedBalance += perpDexState.unsettledProfit;    
        }
        
        if (perpDexState.unsettledLoss > 0) {
            perpDexState.unAllocatedBalance -= perpDexState.unsettledLoss;
        }
    }

    /**
     * @dev Updates profit and loss balances from the vendor.
     * @param balance The updated balance from the vendor.
     */
    function updateProfitFromVender(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

       
    }

    /**
     * @dev Calculates the total options amount based on allocated and unallocated balances.
     * @return The total options amount.
     */
    function getTotalPerpDexAmount() internal view returns (uint256) {
        return 
            perpDexState.unAllocatedBalance +
            (perpDexState.unAllocatedBalance * swapProxy.getPriceOf(optionsAssetAddress, vaultAssetAddress, 6, 6)) / 1e6;
    }
}
