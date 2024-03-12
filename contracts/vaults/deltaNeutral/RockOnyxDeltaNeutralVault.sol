// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../extensions/RockOnyxAccessControl.sol";
import "../../lib/ShareMath.sol";
import "./strategies/RockOynxEthStakeLendStrategy.sol";
import "./strategies/RockOynxPerpDexStrategy.sol";
import "hardhat/console.sol";

contract RockOnyxDeltaNeutralVault is
    RockOnyxAccessControl,
    RockOynxEthStakeLendStrategy,
    RockOynxPerpDexStrategy
{
    uint256 private constant NETWORK_COST = 1e6;
    using SafeERC20 for IERC20;
    using ShareMath for DepositReceipt;
    using LiquidityAmounts for uint256;

    uint256 currentRound;
    uint256 currentRoundWithdrawalAmount;
    mapping(address => DepositReceipt) public depositReceipts;
    mapping(uint256 => uint256) public roundWithdrawalShares;
    mapping(uint256 => uint256) public roundPricePerShares;
    mapping(address => Withdrawal) public withdrawals;
    VaultParams public vaultParams;
    VaultState public vaultState;
    DeltaNeutralAllocateRatio public allocateRatio;

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
    event RoundClosed(
        uint256 roundNumber,
        uint256 totalAssets,
        uint256 totalFee
    );
    event FeeRatesUpdated(uint256 performanceFee, uint256 managementFee);

    constructor(
        address _usdc,
        address _vendorLiquidityProxy,
        address _vendorRewardAddress,
        address _vendorNftPositionAddress,
        address _swapProxy,
        address _optionsVendorProxy,
        address _optionsReceiver,
        address _usdce,
        address _weth,
        address _wstEth,
        address _arb
    )
        RockOynxEthStakeLendStrategy()
        RockOynxPerpDexStrategy()
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);

        currentRound = 0;
        vaultParams = VaultParams(
            6,
            _usdc,
            5_000_000,
            1_000_000 * 1e6,
            10,
            1
        );
        vaultState = VaultState(0, 0, 0, 0, 0, 0, 0);
        allocateRatio = DeltaNeutralAllocateRatio(5000, 5000, 4);
        
        ethStakeLend_Initialize(
            _swapProxy,
            _usdc,
            _weth,
            _wstEth
        );

        perpDex_Initialize(
            _optionsVendorProxy,
            _optionsReceiver,
            _usdce,
            _usdc,
            _swapProxy
        );
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
     * @notice Mints the vault shares for depositor
     * @param amount is the amount of `asset` deposited
     */
    function deposit(uint256 amount) external nonReentrant {
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
     * @notice allocate assets to strategies 
     */
    function allocateAssets() private {
        uint256 depositToEthStakeLendAmount = vaultState.pendingDepositAmount * allocateRatio.ethStakeLendRatio / 10 ** allocateRatio.decimals;
        uint256 depositToPerpDexAmount = vaultState.pendingDepositAmount * allocateRatio.perpDexRatio / 10 ** allocateRatio.decimals;
        vaultState.pendingDepositAmount -= (depositToEthStakeLendAmount + depositToPerpDexAmount);

        depositToEthStakeLendStrategy(depositToEthStakeLendAmount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    /** 
     * @notice recalculate allocate ratio vault
     */
    function recalculateAllocateRatio() private {
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param shares is the number of shares to withdraw
     */
    function initiateWithdrawal(uint256 shares) external nonReentrant {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        require(depositReceipt.shares >= shares, "INVALID_SHARES");
        require(withdrawals[msg.sender].round == currentRound || 
                    withdrawals[msg.sender].shares == 0, "INVALID_WITHDRAW_STATE");

        withdrawals[msg.sender].shares += shares;
        depositReceipt.shares -= shares;
        roundWithdrawalShares[currentRound] += shares;
    }

    /**
     * @notice get profit and loss of user
     */
    function getPnL() public view returns(uint256 profit, uint256 loss) {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        uint256 shares = withdrawals[msg.sender].shares + depositReceipt.shares;
        uint256 currentAmount = shares * _getPricePerShare() / 1e6;

        profit = currentAmount > depositReceipt.depositAmount ? (currentAmount - depositReceipt.depositAmount) * 1e6 / depositReceipt.depositAmount : 0;
        loss = currentAmount < depositReceipt.depositAmount ? (depositReceipt.depositAmount - currentAmount) * 1e6 / depositReceipt.depositAmount : 0;
        return (profit, loss);
    }

    /**
     * @notice get profit and loss of user
     */
    function getDepositAmount() external view returns(uint256) {
        return depositReceipts[msg.sender].depositAmount;
    }

    /**
     * @notice get available withdrawl amount of user
     */
    function getAvailableWithdrawlAmount() external view returns(uint256, bool) {
        return (withdrawals[msg.sender].shares, withdrawals[msg.sender].round == currentRound);
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param shares is the number of shares to withdraw
     */
    function completeWithdrawal(uint256 shares) external nonReentrant {
        require(withdrawals[msg.sender].shares >= shares, "INVALID_SHARES");
        require(vaultState.withdrawPoolAmount > 0, "EXCEED_WITHDRAW_POOL_CAPACITY");

        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            roundPricePerShares[currentRound-1],
            vaultParams.decimals
        );
        
        (uint256 profit,) = getPnL();

        uint256 performanceFee = profit > 0 ? 
            (profit * depositReceipt.depositAmount) * (withdrawals[msg.sender].shares / withdrawals[msg.sender].shares + depositReceipt.shares) * vaultParams.performanceFeeRate / 1e8 : 0;

        vaultState.performanceFeeAmount += performanceFee;
        withdrawAmount -= (performanceFee + NETWORK_COST);
        vaultState.withdrawPoolAmount -=  withdrawAmount;
        depositReceipt.depositAmount -= shares * depositReceipt.depositAmount / (depositReceipt.shares + withdrawals[msg.sender].shares);
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

    /**
     * @notice close round, collect profit and calculate PPS    
     */
    function closeRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
      
    }

    function getVaultState() external view returns(VaultState memory){
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        return vaultState;
    }

    /**
     * @notice get vault fees
     */
    function getManagementFee() private view returns (uint256)
    {
        return (_totalValueLocked() * vaultParams.managementFeeRate) / 100 / 52;
    }

    /**
     * @notice acquire asset form vendor, prepare funds for withdrawal
     */
    function acquireWithdrawalFunds() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

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
        // Access control: Only admin can update the fee rates
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
    function _getPricePerShare() private view returns (uint256) {
        if (currentRound == 0) return 1 * 10 ** vaultParams.decimals;

        return roundPricePerShares[currentRound - 1];
    }

    /**
     * @notice get current price per share
     */
    function pricePerShare() external view returns (uint256) {
        return _getPricePerShare();
    }

    /**
     * @notice get total withdraw amount of current round
     */
    function getRoundWithdrawAmount() external view returns (uint256) {
         _auth(ROCK_ONYX_ADMIN_ROLE);
         
        uint256 withdrawAmount = roundWithdrawalShares[currentRound - 1] * roundPricePerShares[currentRound - 1] / 1e6;
        return withdrawAmount + vaultState.currentRoundFeeAmount;
    }

    /**
     * @notice get total value locked vault
     */
    function totalValueLocked() external view returns (uint256) {
        return _totalValueLocked();
    }

    /**
     * @notice caculate round price pershare
     * @param totalFee is total current round vault fee
     */
    function _caculateRoundPPS(uint256 totalFee) private view returns (uint256) {
        return
            ShareMath.pricePerShare(
                vaultState.totalShares,
                _totalValueLocked() - totalFee,
                vaultParams.decimals
            );
    }

    /**
     * @notice get total value locked vault
     */
    function _totalValueLocked() private view returns (uint256) {
    }

    function allocatedRatio() external view returns (uint256 ethStakeLendRatio, uint256 perpDexRatio) {
        return (allocateRatio.ethStakeLendRatio, allocateRatio.perpDexRatio);
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
