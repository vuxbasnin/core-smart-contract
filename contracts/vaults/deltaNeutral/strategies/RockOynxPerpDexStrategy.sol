// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../interfaces/IAevo.sol";
import "../../../extensions/RockOnyxAccessControl.sol";
import "../../../interfaces/IOptionsVendorProxy.sol";
import "../../../interfaces/ISwapProxy.sol";
import "../structs/DeltaNeutralStruct.sol";
import "hardhat/console.sol";

contract RockOynxPerpDexStrategy is RockOnyxAccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address perpDexStrategyUsdc;
    address perpDexStrategyUsdce;
    address internal optionsReceiver;
    IOptionsVendorProxy internal perpDexVendor;
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

    event RequestFundsPerpDex(
        uint256 acquireAmount
    );

    constructor() {
        perpDexState = PerpDexState(0, 0);
    }

    function perpDex_Initialize(
        address _perpDexAddress,
        address _optionsReceiver,
        address _usdc
    ) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        perpDexStrategyUsdc = _usdc;
        perpDexVendor = IOptionsVendorProxy(_perpDexAddress);
        optionsReceiver = _optionsReceiver;

        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, msg.sender);
        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, optionsReceiver);
    }

    /**
     * @notice submit amount to deposit to Vendor
     */
    function depositToVendor() external payable nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 amount = perpDexState.unAllocatedBalance;
        perpDexState.unAllocatedBalance -= amount;
        IERC20(perpDexStrategyUsdc).approve(address(perpDexVendor), amount);

        perpDexVendor.depositToVendor{value: msg.value}(
            optionsReceiver,
            amount
        );

        perpDexState.perpDexBalance += amount;
        emit PerpDexVendorDeposited(address(perpDexVendor), optionsReceiver, amount);
    }

    function syncDerpDexBalance(uint256 balance) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        perpDexState.perpDexBalance = balance;
    }

    /**
     * @dev Deposit an amount into the options strategy.
     * @param amount The amount to deposit into the options strategy.
     */
    function depositToPerpDexStrategy(uint256 amount) internal {
        perpDexState.unAllocatedBalance += amount;
    }

    function handleFundsFromPerpDex(uint256 amount) internal returns (uint256) {
        if(perpDexState.unAllocatedBalance > amount){
            perpDexState.unAllocatedBalance -= amount;
            return amount;    
        }

        uint256 unAllocatedBalance = perpDexState.unAllocatedBalance;
        perpDexState.unAllocatedBalance = 0;
        IERC20(perpDexStrategyUsdc).safeTransferFrom(msg.sender, address(this), amount - unAllocatedBalance);
        return amount;
    }

    function withdrawFromPerpDex(uint256 amount) internal returns (uint256){
        uint256 amountToAcquire = amount;
        uint256 allownce =  IERC20(perpDexStrategyUsdc).allowance(msg.sender, address(this));
        if (allownce < amountToAcquire)
            amountToAcquire = allownce;

        IERC20(perpDexStrategyUsdc).safeTransferFrom(msg.sender, address(this), amountToAcquire);

        if(amount > amountToAcquire){
            if(perpDexState.unAllocatedBalance > (amount - amountToAcquire)){
                perpDexState.unAllocatedBalance -= (amount - amountToAcquire);
                return amount;
            }else{
                perpDexState.unAllocatedBalance = 0;
                return amount - amountToAcquire - perpDexState.unAllocatedBalance;
            }
        }

        return amount;
    }

    /**
     * @dev Calculates the total options amount based on allocated and unallocated balances.
     * @return The total options amount.
     */
    function getTotalPerpDexAssets() internal view returns (uint256) {
        return 
            perpDexState.unAllocatedBalance + perpDexState.perpDexBalance;
    }
}
