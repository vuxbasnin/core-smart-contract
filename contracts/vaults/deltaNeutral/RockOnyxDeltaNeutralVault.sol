// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "../../lib/ShareMath.sol";
import "./strategies/RockOynxEthStakeLendStrategy.sol";
import "./strategies/RockOynxPerpDexStrategy.sol";
import "./structs/DeltaNeutralStruct.sol";
import "hardhat/console.sol";

contract RockOnyxDeltaNeutralVault is
    RockOnyxAccessControl,
    RockOynxEthStakeLendStrategy,
    RockOynxPerpDexStrategy
{
    uint256 private constant NETWORK_COST = 1e6;
    uint256 private initialPPS;
    using ShareMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => DepositReceipt) private depositReceipts;
    mapping(address => Withdrawal) private withdrawals;
    VaultParams private vaultParams;
    VaultState internal vaultState;
    DeltaNeutralAllocateRatio internal allocateRatio;

    // migration
    DepositReceiptArr[] depositReceiptArr;
    WithdrawalArr[] withdrawalArr;
    // end migration

    /************************************************
     *  EVENTS
     ***********************************************/
    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event InitiateWithdrawal(
        address indexed account,
        uint256 amount,
        uint256 shares
    );
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    event FeeRatesUpdated(uint256 performanceFee, uint256 managementFee);
    event RequestFunds(
        address indexed account,
        uint256 withdrawalAmount,
        uint256 shares
    );

    constructor(
        address _usdc,
        address _swapProxy,
        address _perpDexProxy,
        address _perpDexReceiver,
        address _weth,
        address _wstEth,
        uint256 _initialPPS
    ) RockOynxEthStakeLendStrategy() RockOynxPerpDexStrategy() {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);

        vaultParams = VaultParams(6, _usdc, 5_000_000, 1_000_000 * 1e6, 10, 1);
        vaultState = VaultState(0, 0, 0, 0, 0);
        allocateRatio = DeltaNeutralAllocateRatio(5000, 5000, 4);

        ethStakeLend_Initialize(_swapProxy, _usdc, _weth, _wstEth);

        perpDex_Initialize(_perpDexProxy, _perpDexReceiver, _usdc);

        initialPPS = _initialPPS;
    }

    /**
     * @notice Mints the vault shares for depositor
     * @param amount is the amount of `asset` deposited
     */
    function deposit(uint256 amount) external nonReentrant {
        require(paused == false, "VAULT_HAS_BEEN_PAUSED");
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");
        require(_totalValueLocked() + amount <= vaultParams.cap, "EXCEED_CAP");

        IERC20(vaultParams.asset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 shares = _issueShares(amount);
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        depositReceipt.shares += shares;
        depositReceipt.depositAmount += amount;
        vaultState.pendingDepositAmount += amount;
        vaultState.totalShares += shares;

        allocateAssets();

        emit Deposited(msg.sender, amount, shares);

        // migration
        updateDepositArr(depositReceipts[msg.sender]);
        // end migration
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param shares is the number of shares to withdraw
     */
    function initiateWithdrawal(uint256 shares) external nonReentrant {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        require(depositReceipt.shares >= shares, "INVALID_SHARES");
        require(withdrawals[msg.sender].shares == 0, "INVALID_WITHDRAW_STATE");

        uint256 pps = _getPricePerShare();
        uint256 totalShareAmount = (depositReceipt.shares * pps) / 1e6;
        uint256 totalProfit = totalShareAmount <= depositReceipt.depositAmount
            ? 0
            : (totalShareAmount - depositReceipt.depositAmount) * 1e6;
        uint256 withdrawProfit = (totalProfit * shares) / depositReceipt.shares;
        uint256 performanceFee = withdrawProfit > 0
            ? (withdrawProfit * vaultParams.performanceFeeRate) / 1e14
            : 0;

        depositReceipt.depositAmount -=
            (depositReceipt.depositAmount * shares) /
            depositReceipt.shares;
        depositReceipt.shares -= shares;

        withdrawals[msg.sender].shares = shares;
        withdrawals[msg.sender].pps = pps;
        withdrawals[msg.sender].profit = withdrawProfit;
        withdrawals[msg.sender].performanceFee = performanceFee;
        withdrawals[msg.sender].withdrawAmount = ShareMath.sharesToAsset(
            shares,
            pps,
            vaultParams.decimals
        );

        emit RequestFunds(
            msg.sender,
            withdrawals[msg.sender].withdrawAmount,
            shares
        );

        // migration
        updateDepositArr(depositReceipts[msg.sender]);
        updateWithdrawalArr(withdrawals[msg.sender]);
        // end migration
    }

    /**
     * @notice acquire asset form vendor, prepare funds for withdrawal
     */
    function acquireWithdrawalFunds(uint256 usdAmount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        require(usdAmount <= _totalValueLocked(), "INVALID_ACQUIRE_AMOUNT");
        uint256 ethStakeLendAmount = (usdAmount *
            allocateRatio.ethStakeLendRatio) / 1e4;
        uint256 perpDexAmount = (usdAmount * allocateRatio.perpDexRatio) / 1e4;
        vaultState.withdrawPoolAmount += acquireFundsFromEthStakeLend(
            ethStakeLendAmount
        );
        vaultState.withdrawPoolAmount += acquireFundsFromPerpDex(perpDexAmount);
    }

    function withdrawPerformanceFee() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE); 

        uint256 performanceFeeAmount = (_totalValueLocked() *
            vaultParams.managementFeeRate) /
            100 /
            52;
        uint256 ethStakeLendPerformanceFeeAmount = performanceFeeAmount *
            allocateRatio.ethStakeLendRatio;
        uint256 perpDexFeeAmount = performanceFeeAmount *
            allocateRatio.perpDexRatio;
        ethStakeLendPerformanceFeeAmount = acquireFundsFromEthStakeLend(
            ethStakeLendPerformanceFeeAmount
        );
        perpDexFeeAmount = acquireFundsFromPerpDex(perpDexFeeAmount);
        performanceFeeAmount =
            ethStakeLendPerformanceFeeAmount +
            perpDexFeeAmount;
        vaultState.performanceFeeAmount += performanceFeeAmount;
        vaultState.withdrawPoolAmount += performanceFeeAmount;
    }

    function syncBalance(uint256 perpDexbalance) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        syncEthStakeLendBalance();
        syncPerpDexBalance(perpDexbalance);
        recalculateAllocateRatio();
    }

    /**
     * @notice get vault state for user
     */
    function getUserVaultState()
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        uint256 currentAmount = (depositReceipts[msg.sender].shares *
            _getPricePerShare()) / 1e6;
        uint256 profit = currentAmount >
            depositReceipts[msg.sender].depositAmount
            ? ((currentAmount - depositReceipts[msg.sender].depositAmount) *
                1e6) / depositReceipts[msg.sender].depositAmount
            : 0;
        uint256 loss = currentAmount < depositReceipts[msg.sender].depositAmount
            ? ((depositReceipts[msg.sender].depositAmount - currentAmount) *
                1e6) / depositReceipts[msg.sender].depositAmount
            : 0;
        return (
            depositReceipts[msg.sender].depositAmount,
            depositReceipts[msg.sender].shares,
            profit,
            loss
        );
    }

    /**
     * @notice get withdrawl shares of user
     */
    function getUserWithdrawlShares() external view returns (uint256) {
        return withdrawals[msg.sender].shares;
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param shares is the number of shares to withdraw
     */
    function completeWithdrawal(uint256 shares) external nonReentrant {
        require(withdrawals[msg.sender].shares >= shares, "INVALID_SHARES");
        uint256 withdrawAmount = (shares *
            withdrawals[msg.sender].withdrawAmount) /
            withdrawals[msg.sender].shares;
        uint256 performanceFee = (shares *
            withdrawals[msg.sender].performanceFee) /
            withdrawals[msg.sender].shares;
        withdrawAmount -= (performanceFee + NETWORK_COST);
        require(
            vaultState.withdrawPoolAmount > withdrawAmount,
            "EXCEED_WITHDRAW_POOL_CAPACITY"
        );
        vaultState.performanceFeeAmount += performanceFee;
        vaultState.withdrawPoolAmount -= withdrawAmount;
        withdrawals[msg.sender].withdrawAmount -= withdrawAmount;
        withdrawals[msg.sender].shares -= shares;
        vaultState.totalShares -= shares;

        IERC20(vaultParams.asset).safeTransfer(msg.sender, withdrawAmount);
        emit Withdrawn(
            msg.sender,
            withdrawAmount,
            withdrawals[msg.sender].shares
        );
        // migration
        updateDepositArr(depositReceipts[msg.sender]);
        updateWithdrawalArr(withdrawals[msg.sender]);
        // end migration
    }

    /**
     * @notice claimFee to claim vault fee.
     */
    function claimFee() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        if (
            vaultState.performanceFeeAmount + vaultState.managementFeeAmount >
            vaultState.withdrawPoolAmount
        ) {
            IERC20(vaultParams.asset).safeTransfer(
                msg.sender,
                vaultState.withdrawPoolAmount
            );
            return;
        }

        vaultState.withdrawPoolAmount -= (vaultState.performanceFeeAmount +
            vaultState.managementFeeAmount);
        uint256 claimAmount = vaultState.performanceFeeAmount +
            vaultState.managementFeeAmount;
        vaultState.performanceFeeAmount = 0;
        vaultState.managementFeeAmount = 0;
        IERC20(vaultParams.asset).safeTransfer(msg.sender, claimAmount);
    }

    function getVaultState() external view returns (VaultState memory) {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return vaultState;
    }

    /**
     * @notice Allows admin to update the performance and management fee rates
     * @param _performanceFeeRate The new performance fee rate (in percentage)
     * @param _managementFeeRate The new management fee rate (in percentage)
     */
    function setFeeRates(
        uint256 _performanceFeeRate,
        uint256 _managementFeeRate
    ) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        require(_performanceFeeRate <= 100, "INVALID_PERFORMANCE_FEE_RATE");
        require(_managementFeeRate <= 100, "INVALID_MANAGEMENT_FEE_RATE");
        vaultParams.performanceFeeRate = _performanceFeeRate;
        vaultParams.managementFeeRate = _managementFeeRate;
        emit FeeRatesUpdated(_performanceFeeRate, _managementFeeRate);
    }

    /**
     * @notice get withdraw pool amount of the vault
     */
    function getWithdrawPoolAmount() external view returns (uint256) {
        return vaultState.withdrawPoolAmount;
    }

    /**
     * @notice get number shares of user
     */
    function balanceOf(address owner) external view returns (uint256) {
        return depositReceipts[owner].shares;
    }

    /**
     * @notice get current price per share
     */
    function pricePerShare() external view returns (uint256) {
        return _getPricePerShare();
    }

    /**
     * @notice get total value locked vault
     */
    function totalValueLocked() external view returns (uint256) {
        return _totalValueLocked();
    }

    function allocatedRatio()
        external
        view
        returns (uint256 ethStakeLendRatio, uint256 perpDexRatio)
    {
        return (allocateRatio.ethStakeLendRatio, allocateRatio.perpDexRatio);
    }

    /**
     * @notice Mints the vault shares to the creditor
     * @param amount is the amount to issue shares
     * shares = amount / pricePerShare
     */
    function _issueShares(uint256 amount) private view returns (uint256) {
        return
            ShareMath.assetToShares(
                amount,
                _getPricePerShare(),
                vaultParams.decimals
            );
    }

    /**
     * @notice allocate assets to strategies
     */
    function allocateAssets() private {
        uint256 depositToEthStakeLendAmount = (vaultState.pendingDepositAmount *
            allocateRatio.ethStakeLendRatio) / 10 ** allocateRatio.decimals;
        uint256 depositToPerpDexAmount = vaultState.pendingDepositAmount -
            depositToEthStakeLendAmount;
        vaultState.pendingDepositAmount = 0;

        depositToEthStakeLendStrategy(depositToEthStakeLendAmount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    function rebalanceAsset(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if (getTotalEthStakeLendAssets() > getTotalPerpDexAssets()) {
            rebalanceAssetToPerpDex(amount);
            return;
        }

        rebalanceAssetToEthStakeLend(amount);
    }

    /**
     * @notice Allow admin to settle the covered calls mechanism
     * @param amount the amount in ETH we should sell
     */
    function rebalanceAssetToPerpDex(uint256 amount) private {
        require(
            amount <= getTotalEthStakeLendAssets(),
            "INVALID_ETHSTAKELEND_ASSETS"
        );
        uint256 depositToPerpDexAmount = acquireFundsFromEthStakeLend(amount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    /**
     * @notice Allow admin to settle the covered puts mechanism
     * @param amount the amount in usd we should buy eth
     */
    function rebalanceAssetToEthStakeLend(uint256 amount) private {
        require(amount <= getTotalPerpDexAssets(), "INVALID_PERPDEX_ASSETS");
        uint256 depositToEthStakeLendAmount = acquireFundsFromPerpDex(amount);
        depositToEthStakeLendStrategy(depositToEthStakeLendAmount);
    }

    /**
     * @notice recalculate allocate ratio vault
     */
    function recalculateAllocateRatio() private {
        uint256 totalEthAssets = getTotalEthStakeLendAssets();
        uint256 totalPerpAssets = getTotalPerpDexAssets();
        uint256 tvl = totalEthAssets + totalPerpAssets;
        allocateRatio.ethStakeLendRatio =
            (totalEthAssets * 10 ** allocateRatio.decimals) /
            tvl;
        allocateRatio.perpDexRatio =
            (totalPerpAssets * 10 ** allocateRatio.decimals) /
            tvl;
    }

    /**
     * @notice get vault fees
     */
    function getManagementFee() private view returns (uint256) {
        return (_totalValueLocked() * vaultParams.managementFeeRate) / 100 / 52;
    }

    /**
     * @notice get fee information
     */
    function getFeeInfo()
        external
        view
        returns (
            uint256 depositFee,
            uint256 exitFee,
            uint256 performanceFee,
            uint256 managementFee
        )
    {
        depositFee = 0;
        exitFee = 0;
        performanceFee = vaultParams.performanceFeeRate;
        managementFee = vaultParams.managementFeeRate;
    }

    /**
     * @notice get total value locked vault
     */
    function _totalValueLocked() private view returns (uint256) {
        return
            vaultState.pendingDepositAmount +
            vaultState.withdrawPoolAmount +
            getTotalEthStakeLendAssets() +
            getTotalPerpDexAssets();
    }

    /**
     * @notice get current price per share
     */
    function _getPricePerShare() private view returns (uint256) {
        if (vaultState.totalShares == 0) return initialPPS;

        return
            (_totalValueLocked() * 10 ** vaultParams.decimals) /
            vaultState.totalShares;
    }

    function emergencyShutdown(
        address receiver,
        address tokenAddress,
        uint256 amount
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        IERC20 token = IERC20(tokenAddress);
        require(amount > 0, "INVALID_AMOUNT");
        require(
            token.balanceOf(address(this)) >= amount,
            "INSUFFICIENT_BALANCE"
        );

        bool sent = token.transfer(receiver, amount);
        require(sent, "TOKEN_TRANSFER_FAILED");
    }

    // migration
    function updateDepositArr(DepositReceipt memory depositReceipt) internal {
        for (uint256 i = 0; i < depositReceiptArr.length; i++) {
            if (depositReceiptArr[i].owner == msg.sender) {
                depositReceiptArr[i].depositReceipt = depositReceipt;
                return;
            }
        }

        depositReceiptArr.push(DepositReceiptArr(msg.sender, depositReceipt));
    }
    function updateWithdrawalArr(Withdrawal memory withdrawal) internal {
        for (uint256 i = 0; i < withdrawalArr.length; i++) {
            if (withdrawalArr[i].owner == msg.sender) {
                withdrawalArr[i].withdrawal = withdrawal;
                return;
            }
        }

        withdrawalArr.push(WithdrawalArr(msg.sender, withdrawal));
    }
    function exportVaultState()
        external
        view
        returns (
            DepositReceiptArr[] memory,
            WithdrawalArr[] memory,
            VaultParams memory,
            VaultState memory,
            DeltaNeutralAllocateRatio memory,
            EthStakeLendState memory,
            PerpDexState memory
        )
    {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return (
            depositReceiptArr,
            withdrawalArr,
            vaultParams,
            vaultState,
            allocateRatio,
            ethStakeLendState,
            perpDexState
        );
    }
    function importVaultState(
        DepositReceiptArr[] calldata _depositReceiptArr,
        WithdrawalArr[] calldata _withdrawalArr,
        VaultParams calldata _vaultParams,
        VaultState calldata _vaultState,
        DeltaNeutralAllocateRatio calldata _allocateRatio,
        EthStakeLendState calldata _ethStakeLendState,
        PerpDexState calldata _perpDexState
    ) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        depositReceiptArr = _depositReceiptArr;
        for (uint256 i = 0; i < _depositReceiptArr.length; i++) {
            depositReceipts[_depositReceiptArr[i].owner] = _depositReceiptArr[i]
                .depositReceipt;
        }

        withdrawalArr = _withdrawalArr;
        for (uint256 i = 0; i < _withdrawalArr.length; i++) {
            withdrawals[_withdrawalArr[i].owner] = _withdrawalArr[i].withdrawal;
        }

        vaultParams = _vaultParams;
        vaultState = _vaultState;
        allocateRatio = _allocateRatio;
        ethStakeLendState = _ethStakeLendState;
        perpDexState = _perpDexState;
    }
    // end migration
}
