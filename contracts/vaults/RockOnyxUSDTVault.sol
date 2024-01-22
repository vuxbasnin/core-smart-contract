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
    using SafeERC20 for IERC20;
    using ShareMath for DepositReceipt;

    uint256 currentRound;
    uint256 currentRoundWithdrawalAmount;
    mapping(address => DepositReceipt) public depositReceipts;
    mapping(uint256 => uint256) public roundWithdrawalShares;
    mapping(uint256 => uint256) public roundPricePerShares;
    mapping(uint256 => mapping(address => Withdrawal)) public roundWithdrawals;
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
        require(
            vaultState.pendingDepositAmount + amount <= vaultParams.cap,
            "EXCEED_CAP"
        );
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");

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
                roundPricePerShares[currentRound],
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

        emit Deposited(msg.sender, amount, shares);
    }

    /**
     * @notice AllocateAssets amount
     * 60% stake ETH and WSTETH to staking vender
     * 20% stake USDT to staking vender
     * 20% to option vender
     */
    function allocateAssets() private {
        uint256 depositToEthLPAmount = (vaultState.pendingDepositAmount * 60) /
            100;
        uint256 depositToOptionStrategyAmount = (vaultState
            .pendingDepositAmount * 20) / 100;
        uint256 depositToCashAmount = (vaultState.pendingDepositAmount * 20) /
            100;
        console.log("depositToOptionStrategyAmount %s", depositToOptionStrategyAmount);

        depositToEthLiquidityStrategy(depositToEthLPAmount);
        depositToUsdLiquidityStrategy(depositToCashAmount);
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

        Withdrawal storage withdrawal = roundWithdrawals[currentRound][
            msg.sender
        ];
        withdrawal.shares += shares;
        depositReceipt.shares -= shares;

        roundWithdrawalShares[currentRound] += shares;
        console.log("currentRound ", currentRound);
        console.log(
            "roundWithdrawalShares ",
            roundWithdrawalShares[currentRound]
        );
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     */
    function completeWithdrawal(
        uint256 round,
        uint256 shares
    ) external nonReentrant {
        Withdrawal storage withdrawal = roundWithdrawals[round][msg.sender];
        require(withdrawal.shares > shares, "INVALID_SHARES");

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            roundPricePerShares[round],
            vaultParams.decimals
        );

        require(
            vaultState.withdrawPoolAmount > withdrawAmount,
            "EXCEED_WITHDRAW_POOL_CAPACITY"
        );

        withdrawal.shares -= shares;
        vaultState.withdrawPoolAmount -= withdrawAmount;

        IERC20(vaultParams.asset).safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, withdrawal.shares);
    }

    function closeRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        console.log("=========== closeRound ==========");

        // We store the last locked value before update balance from vendors
        vaultState.lastLockedAmount = _totalValueLocked();
        console.log("vaultState.lastLockedAmount %s", vaultState.lastLockedAmount);

        closeEthLPRound();
        closeUsdLPRound();
        closeOptionsRound();

        // Calculate fees and update vault state
        (uint256 performanceFee, uint256 managementFee) = getVaultFees();
        uint256 totalFee = performanceFee + managementFee;
        console.log("totalFee %s", totalFee);
        
        // Update price per share after fee deduction
        console.log("TVL %s", _totalValueLocked());
        console.log("vaultState.totalShares %s", vaultState.totalShares);
        roundPricePerShares[currentRound] = _getRoundPPS(totalFee);

        console.log("roundPricePerShares", roundPricePerShares[currentRound]);
        currentRound++;
        
        // Emit event for round closure
        emit RoundClosed(currentRound - 1, _totalValueLocked(), totalFee);
    }

    function getVaultFees()
        public
        view
        returns (uint256 performanceFee, uint256 managementFee)
    {
        uint256 netBalance = _totalValueLocked();
        uint256 lastLockedAmount = vaultState.lastLockedAmount;
        console.log("netBalance %s", netBalance);
        console.log("lastLockedAmount %s", lastLockedAmount);

        // Calculate performance fee
        if (netBalance > lastLockedAmount) {
            uint256 profit = netBalance - lastLockedAmount;
            console.log("profit %s", profit);
            performanceFee =
                (profit * vaultParams.performanceFeeRate) /
                100 /
                52; // Weekly rate
            console.log("performanceFee %s", performanceFee);
        }

        // Calculate management fee based on the current balance
        managementFee = (netBalance * vaultParams.managementFeeRate) / 100 / 52; // Weekly rate
        console.log("managementFee %s", managementFee);
    }

    function acquireWithdrawalFunds(uint256 round) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        console.log("roundWithdrawalShares ", roundWithdrawalShares[round]);
        console.log("roundPricePerShares ", roundPricePerShares[round]);

        uint256 withdrawAmount = (roundWithdrawalShares[round] *
            roundPricePerShares[round]) / 1e6;
        uint256 withdrawEthLPAmount = (withdrawAmount * 100) / 100;
        // uint256 withdrawUsdLPAmount = (withdrawAmount * 20) / 100;
        // uint256 withdrawUsdOptionsAmount = (withdrawAmount * 20) / 100;

        console.log("withdrawEthLPAmount ", withdrawEthLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsEthLP(
            withdrawEthLPAmount
        );
        // vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdLP(withdrawUsdLPAmount);
        // vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdOptions(withdrawUsdOptionsAmount);
        console.log("withdrawPoolAmount ", vaultState.withdrawPoolAmount);
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

        // Validate fee rates (optional: add max fee rate limits if needed)
        require(_performanceFeeRate <= 100, "Invalid performance fee rate");
        require(_managementFeeRate <= 100, "Invalid management fee rate");

        // Update state variables
        vaultParams.performanceFeeRate = _performanceFeeRate;
        vaultParams.managementFeeRate = _managementFeeRate;

        // Emit an event if needed (optional)
        emit FeeRatesUpdated(_performanceFeeRate, _managementFeeRate);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return depositReceipts[owner].shares;
    }

    function pricePerShare() external view returns (uint256) {
        if (currentRound == 0) return 1 * 10 ** vaultParams.decimals;

        return roundPricePerShares[currentRound - 1];
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
        return vaultState.pendingDepositAmount + getTotalEthLPAssets() +
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
        require(amount > 0, "Amount must be greater than 0");
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance in contract"
        );

        bool sent = token.transfer(receiver, amount);
        require(sent, "Token transfer failed");
    }

    function emergencyTransferNft(
        address receiver,
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenId);
    }
}
