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
    using ShareMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => DepositReceipt) private depositReceipts;
    uint256 private withdrawalAmount;
    mapping(address => Withdrawal) private withdrawals;
    VaultParams private vaultParams;
    VaultState private vaultState;
    DeltaNeutralAllocateRatio private allocateRatio;

    /************************************************
     *  EVENTS
     ***********************************************/
    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event InitiateWithdrawal(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    event FeeRatesUpdated(uint256 performanceFee, uint256 managementFee);
    event RequestFunds(uint256 ethStakeLendAmount, uint256 perpDexAmount);

    constructor(
        address _usdc,
        address _swapProxy,
        address _perpDexProxy,
        address _perpDexReceiver,
        address _weth,
        address _wstEth
    )
        RockOynxEthStakeLendStrategy()
        RockOynxPerpDexStrategy()
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);

        vaultParams = VaultParams(
            6,
            _usdc,
            5_000_000,
            1_000_000 * 1e6,
            10,
            1
        );
        vaultState = VaultState(0, 0, 0, 0, 0);
        allocateRatio = DeltaNeutralAllocateRatio(5000, 5000, 4);
        
        ethStakeLend_Initialize(
            _swapProxy,
            _usdc,
            _weth,
            _wstEth
        );

        perpDex_Initialize(
            _perpDexProxy,
            _perpDexReceiver,
            _usdc
        );
    }

    /**
     * @notice Mints the vault shares for depositor
     * @param amount is the amount of `asset` deposited
     */
    function deposit(uint256 amount) external nonReentrant {
        require(paused == false, "VAULT_HAS_BEEN_PAUSED");
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");
        require( _totalValueLocked() + amount <= vaultParams.cap, "EXCEED_CAP");

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
        uint256 totalShareAmount = depositReceipt.shares * pps / 1e6;
        uint256 totalProfit = totalShareAmount <= depositReceipt.depositAmount ? 0 :
            (totalShareAmount - depositReceipt.depositAmount) * 1e6 ;
        uint256 withdrawProfit = totalProfit * shares / depositReceipt.shares;
        uint256 performanceFee = withdrawProfit > 0 ? withdrawProfit  * vaultParams.performanceFeeRate / 1e14 : 0;

        depositReceipt.depositAmount -=  depositReceipt.depositAmount * shares / depositReceipt.shares;
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

        uint256 ethStakeLendRatio = getTotalEthStakeLendAssets() * 1e4  / (getTotalEthStakeLendAssets() + getTotalPerpDexAssets());
        uint256 ethStakeLendAmount = withdrawals[msg.sender].withdrawAmount * ethStakeLendRatio / 1e4;        
        uint256 perpDexAmount = withdrawals[msg.sender].withdrawAmount - ethStakeLendAmount;

        vaultState.totalShares -= shares;

        console.log('withdrawAmount %s', withdrawals[msg.sender].withdrawAmount);
        console.log('pps %s', withdrawals[msg.sender].pps);
        console.log('ethStakeLendAmount %s %s', ethStakeLendAmount, perpDexAmount);

        emit RequestFunds(ethStakeLendAmount, perpDexAmount);
    }

    /**
     * @notice acquire asset form vendor, prepare funds for withdrawal
     */
    function handleWithdrawalFunds(uint256 ethStakeLendAmount, uint256 perpDexAmount) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        vaultState.withdrawPoolAmount += handleFundsFromEthStakeLend(ethStakeLendAmount);
        vaultState.withdrawPoolAmount += handleFundsFromPerpDex(perpDexAmount);
    }

    function withdrawPerformanceFee() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 performanceFeeAmount = (_totalValueLocked() * vaultParams.managementFeeRate) / 100 / 52;
        uint256 ethStakeLendPerformanceFeeAmount = performanceFeeAmount * allocateRatio.ethStakeLendRatio;
        uint256 perpDexFeeAmount = performanceFeeAmount * allocateRatio.perpDexRatio;

        ethStakeLendPerformanceFeeAmount = handleFundsFromEthStakeLend(ethStakeLendPerformanceFeeAmount);
        perpDexFeeAmount = handleFundsFromPerpDex(perpDexFeeAmount);

        performanceFeeAmount = ethStakeLendPerformanceFeeAmount + perpDexFeeAmount;
        vaultState.performanceFeeAmount += performanceFeeAmount;
        vaultState.withdrawPoolAmount += performanceFeeAmount;
    }

    /**
     * @notice get vault state for user
     */
    function getUserVaultState() external view returns(uint256, uint256, uint256, uint256) {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        uint256 currentAmount = depositReceipt.shares * _getPricePerShare() / 1e6;

        uint256 profit = currentAmount > depositReceipt.depositAmount ? (currentAmount - depositReceipt.depositAmount) * 1e6 / depositReceipt.depositAmount : 0;
        uint256 loss = currentAmount < depositReceipt.depositAmount ? (depositReceipt.depositAmount - currentAmount) * 1e6 / depositReceipt.depositAmount : 0;

        return (depositReceipts[msg.sender].depositAmount, depositReceipts[msg.sender].shares, profit, loss);
    }

    /**
     * @notice get withdrawl shares of user
     */
    function getUserWithdrawlShares() external view returns(uint256) {
        return withdrawals[msg.sender].shares;
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param shares is the number of shares to withdraw
     */
    function completeWithdrawal(uint256 shares) external nonReentrant {
        require(withdrawals[msg.sender].shares >= shares, "INVALID_SHARES");

        uint256 withdrawAmount = shares * withdrawals[msg.sender].withdrawAmount / withdrawals[msg.sender].shares;
        uint256 performanceFee = shares * withdrawals[msg.sender].performanceFee / withdrawals[msg.sender].shares;
        withdrawAmount -= (performanceFee + NETWORK_COST);

        require(vaultState.withdrawPoolAmount > withdrawAmount, "EXCEED_WITHDRAW_POOL_CAPACITY");

        vaultState.performanceFeeAmount += performanceFee;
        vaultState.withdrawPoolAmount -=  withdrawAmount;
        withdrawals[msg.sender].withdrawAmount -= withdrawAmount;
        withdrawals[msg.sender].shares -= shares;

        IERC20(vaultParams.asset).safeTransfer(msg.sender, withdrawAmount);
        emit Withdrawn(msg.sender, withdrawAmount, withdrawals[msg.sender].shares);
    }

    /**
     * @notice claimFee to claim vault fee.
     */
    function claimFee() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        if(vaultState.performanceFeeAmount + vaultState.managementFeeAmount > vaultState.withdrawPoolAmount)
        {
            IERC20(vaultParams.asset).safeTransfer(msg.sender, vaultState.withdrawPoolAmount);
            return;
        }
            
        vaultState.withdrawPoolAmount -= (vaultState.performanceFeeAmount + vaultState.managementFeeAmount);
        uint256 claimAmount = vaultState.performanceFeeAmount + vaultState.managementFeeAmount;
        vaultState.performanceFeeAmount = 0;
        vaultState.managementFeeAmount = 0;
        IERC20(vaultParams.asset).safeTransfer(msg.sender, claimAmount);
    }

    function getVaultState() external view returns(VaultState memory){
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

    function allocatedRatio() external view returns (uint256 ethStakeLendRatio, uint256 perpDexRatio) {
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
        uint256 depositToEthStakeLendAmount = vaultState.pendingDepositAmount * allocateRatio.ethStakeLendRatio / 10 ** allocateRatio.decimals;
        uint256 depositToPerpDexAmount = vaultState.pendingDepositAmount - depositToEthStakeLendAmount;
        vaultState.pendingDepositAmount = 0;

        depositToEthStakeLendStrategy(depositToEthStakeLendAmount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    function rebalanceAsset(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if(getTotalEthStakeLendAssets() > getTotalPerpDexAssets()){
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
        require(amount <= getTotalEthStakeLendAssets(), "INVALID_ETHSTAKELEND_POSITION_SIZE");

        uint256 depositToPerpDexAmount = handleFundsFromEthStakeLend(amount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    /**
     * @notice Allow admin to settle the covered puts mechanism
     * @param amount the amount in usd we should buy eth 
     */
    function rebalanceAssetToEthStakeLend(uint256 amount) private {
        require(amount <= getTotalPerpDexAssets(), "INVALID_PERPDEX_POSITION_SIZE");

        uint256 depositToEthStakeLendAmount = handleFundsFromPerpDex(amount);
        depositToPerpDexStrategy(depositToEthStakeLendAmount);
    }

    /**
     * @notice get vault fees
     */
    function getManagementFee() private view returns (uint256) {
        return (_totalValueLocked() * vaultParams.managementFeeRate) / 100 / 52;
    }

    /**
     * @notice get total value locked vault
     */
    function _totalValueLocked() private view returns (uint256) {
        return
            vaultState.pendingDepositAmount + 
            getTotalEthStakeLendAssets() +
            getTotalPerpDexAssets();
    }

    /**
     * @notice get current price per share
     */
    function _getPricePerShare() private view returns (uint256) {
        if(vaultState.totalShares == 0) 
            return 1 * 10 ** vaultParams.decimals;

        return _totalValueLocked() * 10 ** vaultParams.decimals / vaultState.totalShares;
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
}
