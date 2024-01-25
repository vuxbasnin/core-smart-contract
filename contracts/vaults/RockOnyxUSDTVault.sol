// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../strategies/RockOnyxEthLiquidityStrategy.sol";
import "../strategies/RockOnyxOptionsStrategy.sol";
import "../strategies/RockOynxUsdLiquidityStrategy.sol";
import "hardhat/console.sol";

contract RockOnyxUSDTVault is
    IERC721Receiver,
    RockOnyxAccessControl,
    RockOnyxEthLiquidityStrategy,
    RockOnyxOptionStrategy,
    RockOynxUsdLiquidityStrategy
{
    uint256 private constant PRICE_IMPACT = 10; // 0.01% price impact
    uint256 private constant MAX_SLIPPAGE = 500; // 0.5% slippage
    uint256 private constant NETWORK_COST = 1e6; // Network cost in smallest unit of USDC (1 USDC), will improve later on

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
        address _vendorNftPositionddress,
        address _swapProxy,
        address _optionsVendorProxy,
        address _optionsReceiver,
        address _usdce,
        address _weth,
        address _wstEth
    )
        RockOnyxEthLiquidityStrategy()
        RockOnyxOptionStrategy()
        RockOynxUsdLiquidityStrategy()
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);

        currentRound = 0;
        vaultParams = VaultParams(
            6,
            _usdc,
            10_000_000,
            1_000_000 * 10 ** 6,
            10,
            1
        );
        vaultState = VaultState(0, 0, 0, 0);

        options_Initialize(
            _optionsVendorProxy,
            _optionsReceiver,
            _usdce,
            _usdc,
            _swapProxy
        );
        ethLP_Initialize(
            _vendorLiquidityProxy,
            _vendorNftPositionddress,
            _swapProxy,
            _usdc,
            _weth,
            _wstEth
        );
        usdLP_Initialize(
            _vendorLiquidityProxy,
            _vendorNftPositionddress,
            _swapProxy,
            _usdc,
            _usdce
        );
    }

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {}

    /**
     * @notice Mints the vault shares to the creditor
     * @param amount is the amount of `asset` deposited
     * @param creditor is the address to receieve the deposit
     */
    function _depositFor(
        uint256 amount,
        address creditor
    ) private returns (uint256) {
        uint256 shares = _issueShares(amount);
        DepositReceipt storage depositReceipt = depositReceipts[creditor];
        depositReceipt.shares += shares;
        vaultState.pendingDepositAmount += amount;
        vaultState.totalShares += shares;
        return shares;
    }

    /**
     * @notice Mints the vault shares to the creditor
     * shares = amount / pricePerShare <=> amount / (vaultState.totalAssets / vaultState.totalShares)
     */
    function _issueShares(uint256 amount) private view returns (uint256) {
        if (vaultState.pendingDepositAmount <= 0) return amount;

        return
            ShareMath.assetToShares(
                amount,
                roundPricePerShares[currentRound-1],
                vaultParams.decimals
            );
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");
        require(
            vaultState.pendingDepositAmount + amount <= vaultParams.cap,
            "EXCEED_CAP"
        );

        IERC20(vaultParams.asset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 shares = _depositFor(amount, msg.sender);

        allocateAssets();
        
        emit Deposited(msg.sender, amount, shares);
    }

    /**
     * @notice AllocateAssets amount
     * 60% stake ETH and WSTETH to staking vender
     * 20% stake USDT to staking vender
     * 20% to option vender
     */
    function allocateAssets() private {
        uint256 depositToEthLPAmount = (vaultState.pendingDepositAmount * 60) / 100;
        uint256 depositToUsdLPmount = (vaultState.pendingDepositAmount * 20) / 100;
        uint256 depositToOptionStrategyAmount = vaultState.pendingDepositAmount - (depositToEthLPAmount + depositToUsdLPmount);

        depositToEthLiquidityStrategy(depositToEthLPAmount);
        depositToUsdLiquidityStrategy(depositToUsdLPmount);
        depositToOptionsStrategy(depositToOptionStrategyAmount);

        vaultState.pendingDepositAmount = 0;
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
     * @notice get available withdrawl amount for sender
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

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            roundPricePerShares[currentRound-1],
            vaultParams.decimals
        );

        require(
            vaultState.withdrawPoolAmount > withdrawAmount,
            "EXCEED_WITHDRAW_POOL_CAPACITY"
        );

        withdrawals[msg.sender].shares -= shares;
        vaultState.withdrawPoolAmount -= withdrawAmount;

        IERC20(vaultParams.asset).safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, withdrawals[msg.sender].shares);
    }

    /**
     * @notice close round, collect profit and calculate PPS 
     */
    function closeRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        vaultState.lastLockedAmount = _totalValueLocked();

        closeEthLPRound();
        closeUsdLPRound();
        closeOptionsRound();

        (uint256 performanceFee, uint256 managementFee) = getVaultFees();
        uint256 totalFee = performanceFee + managementFee;
        
        roundPricePerShares[currentRound] = _getRoundPPS(totalFee);

        emit RoundClosed(currentRound , _totalValueLocked(), totalFee);

        currentRound++;
    }

    /**
     * @notice get vault fees
     */
    function getVaultFees() private view returns (uint256 performanceFee, uint256 managementFee)
    {
        uint256 netBalance = _totalValueLocked();
        uint256 lastLockedAmount = vaultState.lastLockedAmount;

        if (netBalance > lastLockedAmount) {
            uint256 profit = netBalance - lastLockedAmount;
            performanceFee =
                (profit * vaultParams.performanceFeeRate) /
                100 /
                52;
        }

        managementFee = (netBalance * vaultParams.managementFeeRate) / 100 / 52;
    }

    /**
     * @notice acquire asset form vender, prepare funds for withdrawal
     */
    function acquireWithdrawalFunds() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        uint256 withdrawAmount = roundWithdrawalShares[currentRound - 1] * roundPricePerShares[currentRound - 1] / 1e6;
        uint256 withdrawAmountWithSlippageAndImpact = (withdrawAmount * (1e5 + MAX_SLIPPAGE + PRICE_IMPACT)) / 1e5 + NETWORK_COST;
        (uint256 performanceFee, uint256 managementFee) = getVaultFees();
        uint256 withdrawAmountIncluceFees = withdrawAmountWithSlippageAndImpact + performanceFee + managementFee;
        if(withdrawAmountIncluceFees > vaultState.withdrawPoolAmount)
            withdrawAmountIncluceFees -= vaultState.withdrawPoolAmount;

        uint256 withdrawEthLPAmount = (withdrawAmountIncluceFees * 60) / 100;
        uint256 withdrawUsdLPAmount = (withdrawAmountIncluceFees * 20) / 100;
        uint256 withdrawUsdOptionsAmount = (withdrawAmountIncluceFees * 20) / 100;
        
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsEthLP(withdrawEthLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdLP(withdrawUsdLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdOptions(withdrawUsdOptionsAmount);
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

    function balanceOf(address owner) external view returns (uint256) {
        return depositReceipts[owner].shares;
    }

    function pricePerShare() external view returns (uint256) {
        if (currentRound == 0) return 1 * 10 ** vaultParams.decimals;

        return roundPricePerShares[currentRound - 1];
    }

    function getRoundWithdrawAmount() external view returns (uint256) {
        uint256 withdrawAmount = roundWithdrawalShares[currentRound - 1] * roundPricePerShares[currentRound - 1] / 1e6;
        uint256 withdrawAmountWithSlippageAndImpact = (withdrawAmount * (1e5 + MAX_SLIPPAGE + PRICE_IMPACT)) / 1e5 + NETWORK_COST;
        (uint256 performanceFee, uint256 managementFee) = getVaultFees();
        uint256 withdrawAmountIncluceFees = withdrawAmountWithSlippageAndImpact + performanceFee + managementFee;
        if(withdrawAmountIncluceFees > vaultState.withdrawPoolAmount)
            withdrawAmountIncluceFees -= vaultState.withdrawPoolAmount;

        return withdrawAmountIncluceFees;
    }

    function totalValueLocked() external view returns (uint256) {
        return _totalValueLocked();
    }

    function _getRoundPPS(uint256 totalFee) private view returns (uint256) {
        return
            ShareMath.pricePerShare(
                vaultState.totalShares,
                _totalValueLocked() - totalFee,
                vaultParams.decimals
            );
    }

    function _totalValueLocked() private view returns (uint256) {
        return vaultState.pendingDepositAmount + 
            getTotalEthLPAssets() +
            getTotalUsdLPAssets() +
            getTotalOptionsAmount();
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
