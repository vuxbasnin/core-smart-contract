// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../strategies/RockOnyxEthLiquidityStrategy.sol";
import "../strategies/RockOnyxOptionsStrategy.sol";
import "hardhat/console.sol";

contract RockOnyxUSDTVault is
    RockOnyxAccessControl,
    RockOnyxEthLiquidityStrategy,
    RockOnyxOptionStrategy
{
    using SafeERC20 for IERC20;
    using ShareMath for DepositReceipt;

    mapping(address => DepositReceipt) public depositReceipts;
    mapping(address => Withdrawal) public withdrawals;
    VaultParams public vaultParams;
    VaultState public vaultState;

    /************************************************
     *  EVENTS
     ***********************************************/
    event Deposit(address indexed account, uint256 amount, uint256 shares);
    event InitiateWithdraw(
        address indexed account,
        uint256 amount,
        uint256 shares
    );
    event Withdraw(address indexed account, uint256 amount, uint256 shares);
    event RoundClosed(int256 pnl);

    constructor(
        address _asset,
        address _vendorLiquidityProxy,
        address _vendorNftPositionddress,
        address _swapProxy,
        address _optionsVendorProxy,
        address _optionsReceiver,
        address _optionsAssetAddress,
        address _weth,
        address _wstEth
    )
        RockOnyxEthLiquidityStrategy(
            _vendorLiquidityProxy,
            _vendorNftPositionddress,
            _swapProxy,
            _asset,
            _weth,
            _wstEth
        )
        RockOnyxOptionStrategy(
            _optionsVendorProxy,
            _optionsReceiver,
            _optionsAssetAddress,
            _asset,
            _swapProxy
        )
    {
        vaultParams = VaultParams(6, _asset, 1_00, 1_000_000 * 10 **6);
        vaultState = VaultState(0, 0);

        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Mints the vault shares to the creditor
     * @param amount is the amount of `asset` deposited
     * @param creditor is the address to receieve the deposit
     */
    function _depositFor(
        uint256 amount,
        address creditor
    ) private returns (uint256) {
        require(vaultState.totalAssets + amount <= vaultParams.cap, "EXCEED_CAP");
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");

        uint256 shares = _issueShares(amount);
        DepositReceipt storage depositReceipt = depositReceipts[creditor];
        depositReceipt.shares += shares;

        vaultState.totalAssets += amount;
        vaultState.totalShares += shares;
        console.log(
            "Vault Deposit vaultState.totalShares %s, shares %s",
            vaultState.totalShares,
            shares
        );

        return shares;
    }

    /**
     * @notice Mints the vault shares to the creditor
     * shares = amount / pricePerShare <=> amount / (vaultState.totalAssets / vaultState.totalShares)
     */
    function _issueShares(uint256 amount) private view returns (uint256) {
        if (vaultState.totalAssets <= 0) return amount;

        return
            ShareMath.assetToShares(
                amount,
                pricePerShare(),
                vaultParams.decimals
            );
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "INVALID_DEPOSIT_AMOUNT");

        uint256 shares = _depositFor(amount, msg.sender);

        // An approve() by the msg.sender is required beforehand
        IERC20(vaultParams.asset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        allocateAssets();

        emit Deposit(msg.sender, amount, shares);
    }

    /**
     * @notice AllocateAssets amount
     * 60% stake ETH and WSTETH to staking vender
     * 20% stake USDT to staking vender
     * 20% to option vender
     */
    function allocateAssets() private {
        uint256 depositToEthLiquidityStrategyAmount = (vaultState.totalAssets * 60) / 100;
        uint256 depositToOptionStrategyAmount = (vaultState.totalAssets * 20) / 100;
        uint256 depositToCashAmount = (vaultState.totalAssets * 20) / 100;

        console.log(
            "Handle allocateAssets, depositToOptionStrategyAmount = %s, vaultState.totalAssets= %s",
            depositToOptionStrategyAmount,
            vaultState.totalAssets
        );

        // depositToEthLiquidityStrategy(depositToEthLiquidityStrategyAmount);
        depositToOptionsStrategy(depositToOptionStrategyAmount);

        vaultState.totalAssets -= (depositToEthLiquidityStrategyAmount +
            depositToOptionStrategyAmount +
            depositToCashAmount);
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param numShares is the number of shares to withdraw
     */
    function initiateWithdraw(uint256 numShares) external nonReentrant {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        console.log(
            "Withdraw amount = %d, user shares = %d",
            numShares,
            depositReceipt.shares
        );

        require(depositReceipt.shares >= numShares, "INVALID_SHARES");

        Withdrawal storage withdrawal = withdrawals[msg.sender];
        withdrawal.shares += numShares;
        depositReceipt.shares -= numShares;
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     */
    function completeWithdraw() external nonReentrant {
        address withdrawaler = msg.sender;
        
        console.log("Start completeWithdraw");
        Withdrawal storage withdrawal = withdrawals[withdrawaler];

        // This checks if there is a withdrawal
        require(withdrawal.shares > 0, "NOT_INITIATED");

        console.log("vaultState.totalAssets = %s", vaultState.totalAssets);
        console.log("vaultState.totalShares = %s", vaultState.totalShares);
        console.log(
            "pps = %s",
            vaultState.totalAssets / vaultState.totalShares
        );

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            withdrawal.shares,
            pricePerShare(),
            vaultParams.decimals
        );

        // We leave the round number as non-zero to save on gas for subsequent writes
        withdrawal.shares = 0;

        console.log("withdrawAmount = %s", withdrawAmount);

        emit Withdraw(withdrawaler, withdrawAmount, withdrawal.shares);

        IERC20(vaultParams.asset).safeTransfer(withdrawaler, withdrawAmount);
    }

    function balanceOf(address account) public view returns (uint256) {
        return depositReceipts[account].shares;
    }

    function pricePerShare() public view returns (uint256) {
        return
            ShareMath.pricePerShare(
                vaultState.totalShares,
                totalValueLocked(),
                vaultParams.decimals
            );
    }

    function totalValueLocked() public view returns (uint256) {
        return totalAllocatedAmount() + getTotalAssets();
    }
}
