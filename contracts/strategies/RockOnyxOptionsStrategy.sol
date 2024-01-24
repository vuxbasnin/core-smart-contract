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

    // Constants for fees and slippage
    uint256 private constant PRICE_IMPACT = 10; // 0.01% price impact
    uint256 private constant MAX_SLIPPAGE = 500; // 0.5% slippage
    uint256 private constant NETWORK_COST = 1e6; // Network cost in smallest unit of USDC (1 USDC), will improve later on

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
        optionsState = OptionsStrategyState(0, 0, 0);
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

    /**
     * @notice Acquires withdrawal funds in USDC options
     * @param withdrawUsdOptionsAmount The requested withdrawal amount in USDC
     */
    function acquireWithdrawalFundsUsdOptions(uint256 withdrawUsdOptionsAmount) internal returns (uint256) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 totalAmountWithSlippageAndImpact = (withdrawUsdOptionsAmount * (1e5 + MAX_SLIPPAGE + PRICE_IMPACT)) / 1e5;
        uint256 totalAmountRequired = totalAmountWithSlippageAndImpact + NETWORK_COST;
        uint256 amountToWithdrawInOptionsAsset = (totalAmountRequired * 1e6) / swapProxy.getPriceOf(vaultAssetAddress, optionsAssetAddress, 6, 6);
        
        require(optionsState.unAllocatedBalance >= amountToWithdrawInOptionsAsset, "INSUFFICIENT_UNALLOCATED_BALANCE");
        IERC20(optionsAssetAddress).approve(address(swapProxy), amountToWithdrawInOptionsAsset);

        uint256 withdrawalAmountInVaultAsset = swapProxy.swapTo(
            address(this),
            optionsAssetAddress,
            amountToWithdrawInOptionsAsset,
            vaultAssetAddress
        );
        
        // Verify the swap result
        require(withdrawalAmountInVaultAsset > 0, "SWAP_FAILED");

        optionsState.unAllocatedBalance -= amountToWithdrawInOptionsAsset;
        
        return withdrawalAmountInVaultAsset;
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor() external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        console.log("================ depositToVendor =============");
        IERC20(optionsAssetAddress).approve(address(optionsVendor), optionsState.unAllocatedBalance);

        optionsVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            optionsState.unAllocatedBalance            
        );

        emit OptionsVendorDeposited(address(optionsVendor), optionsReceiver, optionsState.unAllocatedBalance);

        optionsState.allocatedBalance += optionsState.unAllocatedBalance;
        optionsState.unAllocatedBalance = 0;
    }

    function handlePostWithdrawalFromVendor(
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "INVALID_WITHDRAW_AMOUNT");
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        IERC20(optionsAssetAddress).safeTransferFrom(msg.sender, address(this), amount);

        emit OptionsBalanceChanged(optionsState.unAllocatedBalance, optionsState.unAllocatedBalance + amount);

        optionsState.unAllocatedBalance += amount;
        optionsState.allocatedBalance -= amount;
    }

    function closeOptionsRound() internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsState.allocatedBalance = optionsState.unsettledProfit > 0 ? 
            optionsState.allocatedBalance + uint256(optionsState.unsettledProfit) : 
            optionsState.allocatedBalance - uint256(-optionsState.unsettledProfit);
        optionsState.unsettledProfit = 0;
    }

    function updateProfitFromVender(uint256 balance) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        optionsState.unsettledProfit = int256(balance) - int256(optionsState.allocatedBalance);
    }

    function getTotalOptionsAmount() internal view returns (uint256) {
        uint256 totalAssets = ((optionsState.allocatedBalance + optionsState.unAllocatedBalance) *
                swapProxy.getPriceOf(optionsAssetAddress, vaultAssetAddress, 6, 6)) / 1e6;

        console.log('getTotalOptionsAmount totalAssets: ', totalAssets);
        return totalAssets;
    }
}
