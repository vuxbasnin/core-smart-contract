// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "../../lib/ShareMath.sol";
import "./strategies/RockOnyxEthLiquidityStrategy.sol";
import "./strategies/RockOnyxOptionsStrategy.sol";
import "./strategies/RockOynxUsdLiquidityStrategy.sol";
import "./BaseRockOnyxOptionWheelVault.sol";
import "../../extensions/RockOnyx/BaseSwapVault.sol";
import "hardhat/console.sol";

contract RockOnyxUSDTVault is BaseSwapVault, BaseRockOnyxOptionWheelVault {
    uint256 private constant NETWORK_COST = 1e6;
    using SafeERC20 for IERC20;
    using ShareMath for DepositReceipt;
    using LiquidityAmounts for uint256;

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
        address _admin,
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
        address _arb,
        uint256 _initialPPS,
        address _uniSwapProxy,
        address[] memory _token0s,
        address[] memory _token1s,
        uint24[] memory _fees
    )
        RockOnyxEthLiquidityStrategy()
        RockOnyxOptionStrategy()
        RockOynxUsdLiquidityStrategy()
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, _admin);
        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, _admin);
        _grantRole(ROCK_ONYX_OPTIONS_TRADER_ROLE, _optionsReceiver);

        currentRound = 0;
        vaultParams = VaultParams(6, _usdc, 5_000_000, 1_000_000 * 1e6, 10, 1);
        vaultState = VaultState(0, 0, 0, 0, 0, 0, 0);
        allocateRatio = AllocateRatio(6000, 2000, 2000, 4);

        baseSwapVault_Initialize(_uniSwapProxy, _token0s, _token1s, _fees);
        options_Initialize(_optionsVendorProxy, _optionsReceiver, _usdc);
        ethLP_Initialize(
            _vendorLiquidityProxy,
            _vendorRewardAddress,
            _vendorNftPositionAddress,
            _swapProxy,
            _usdc,
            _weth,
            _wstEth,
            _arb
        );
        usdLP_Initialize(
            _vendorLiquidityProxy,
            _vendorNftPositionAddress,
            _swapProxy,
            _usdc,
            _usdce
        );

        if (_initialPPS > 0) {
            currentRound = 1;
            roundPricePerShares[currentRound - 1] = _initialPPS;
        }
    }

    /**
     * @notice Mints the vault shares for depositor
     * @param amount is the amount of `asset` deposited
     */
    function deposit(uint256 amount, address tokenIn, address transitToken) external nonReentrant {
        require(paused == false, "PAUSED");
        
        uint256 assetDepositAmount = (tokenIn == vaultParams.asset) ? amount : 
                            (tokenIn == transitToken) ? amount * swapProxy.getPriceOf(tokenIn, vaultParams.asset) / 10 ** (ERC20(tokenIn).decimals()) :
                            (amount * swapProxy.getPriceOf(tokenIn, transitToken) * swapProxy.getPriceOf(transitToken, vaultParams.asset)) / 10 ** (ERC20(tokenIn).decimals() + (ERC20(transitToken).decimals()));

        require(assetDepositAmount >= vaultParams.minimumSupply, "MIN_AMOUNT");
        require(_totalValueLocked() + assetDepositAmount <= vaultParams.cap, "EXCEED_CAP");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
        if(tokenIn != vaultParams.asset){
            if(tokenIn != transitToken){
                IERC20(tokenIn).approve(address(swapProxy), amount);
                amount = swapProxy.swapTo(
                    address(this),
                    address(tokenIn),
                    amount,
                    address(transitToken),
                    getFee(address(tokenIn), address(transitToken))
                );
            }

            IERC20(transitToken).approve(address(swapProxy), amount);
            amount = swapProxy.swapTo(
                address(this),
                address(transitToken),
                amount,
                address(vaultParams.asset),
                getFee(address(transitToken), address(vaultParams.asset))
            );
        }

        uint256 shares = ShareMath.assetToShares(
            amount,
            _getPricePerShare(),
            vaultParams.decimals
        );
        depositReceipts[msg.sender].shares += shares;
        depositReceipts[msg.sender].depositAmount += amount;
        vaultState.pendingDepositAmount += amount;
        vaultState.totalShares += shares;
        allocateAssets();
        emit Deposited(msg.sender, amount, shares);

        // migration
        updateDepositArr(depositReceipts[msg.sender]);
        // end migration
    }

    /**
     * @notice allocate assets to strategies
     */
    function allocateAssets() private {
        uint256 depositToEthLPAmount = (vaultState.pendingDepositAmount *
            allocateRatio.ethLPRatio) / 10 ** allocateRatio.decimals;
        uint256 depositToUsdLPAmount = (vaultState.pendingDepositAmount *
            allocateRatio.usdLPRatio) / 10 ** allocateRatio.decimals;
        uint256 depositOptionsAmount = (vaultState.pendingDepositAmount *
            allocateRatio.optionsRatio) / 10 ** allocateRatio.decimals;
        vaultState.pendingDepositAmount -= (depositToEthLPAmount +
            depositToUsdLPAmount +
            depositOptionsAmount);

        depositToEthLiquidityStrategy(depositToEthLPAmount);
        depositToUsdLiquidityStrategy(depositToUsdLPAmount);
        depositToOptionsStrategy(depositOptionsAmount);
    }

    /**
     * @notice recalculate allocate ratio vault
     */
    function recalculateAllocateRatio() private {
        uint256 tvl = getTotalEthLPAssets() + getTotalUsdLPAssets() + getTotalOptionsAmount();
        allocateRatio.ethLPRatio = (getTotalEthLPAssets() * 10 ** allocateRatio.decimals) / tvl;
        allocateRatio.usdLPRatio = (getTotalUsdLPAssets() * 10 ** allocateRatio.decimals) / tvl;
        allocateRatio.optionsRatio = (getTotalOptionsAmount() * 10 ** allocateRatio.decimals) / tvl;
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param shares is the number of shares to withdraw
     */
    function initiateWithdrawal(uint256 shares) external nonReentrant {
        require(depositReceipts[msg.sender].shares >= shares, "INV_SHARES");
        require(withdrawals[msg.sender].round == currentRound || withdrawals[msg.sender].shares == 0, "INV_SHARES");

        withdrawals[msg.sender].shares += shares;
        withdrawals[msg.sender].round = currentRound;
        depositReceipts[msg.sender].shares -= shares;
        roundWithdrawalShares[currentRound] += shares;

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            _getPricePerShare(),
            vaultParams.decimals
        );
        emit InitiateWithdrawal(
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
     * @notice get profit and loss of user
     */
    function getPnL() public view returns (uint256 profit, uint256 loss) {
        uint256 shares = withdrawals[msg.sender].shares + depositReceipts[msg.sender].shares;
        uint256 currentAmount = (shares * _getPricePerShare()) / 1e6;

        profit = currentAmount > depositReceipts[msg.sender].depositAmount
            ? ((currentAmount - depositReceipts[msg.sender].depositAmount) *
                1e6) / depositReceipts[msg.sender].depositAmount
            : 0;
        loss = currentAmount < depositReceipts[msg.sender].depositAmount
            ? ((depositReceipts[msg.sender].depositAmount - currentAmount) *
                1e6) / depositReceipts[msg.sender].depositAmount
            : 0;
    }

    /**
     * @notice get profit and loss of user
     */
    function getDepositAmount() external view returns (uint256) {
        return depositReceipts[msg.sender].depositAmount;
    }

    /**
     * @notice get available withdrawl amount of user
     */
    function getAvailableWithdrawlAmount() external view returns (uint256, bool) {
        return (
            withdrawals[msg.sender].shares,
            withdrawals[msg.sender].round == currentRound
        );
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     * @param shares is the number of shares to withdraw
     */
    function completeWithdrawal(uint256 shares) external nonReentrant {
        require(withdrawals[msg.sender].round < currentRound, "INV_WD_ROUND");
        require(withdrawals[msg.sender].shares >= shares, "INV_SHARES");

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            roundPricePerShares[withdrawals[msg.sender].round],
            vaultParams.decimals
        );
        (uint256 profit, ) = getPnL();
        uint withdrawProfit = profit > 0
            ? (profit * withdrawals[msg.sender].shares) /
                (withdrawals[msg.sender].shares +
                    depositReceipts[msg.sender].shares)
            : 0;
        uint256 performanceFee = withdrawProfit > 0
            ? (withdrawProfit * vaultParams.performanceFeeRate) / 1e2
            : 0;
        vaultState.performanceFeeAmount += performanceFee;
        withdrawAmount -= (performanceFee + NETWORK_COST);

        require(vaultState.withdrawPoolAmount > withdrawAmount, "EXD_WD_POOL_CAP");
        
        vaultState.withdrawPoolAmount -= withdrawAmount;
        depositReceipts[msg.sender].depositAmount -=
            (shares * depositReceipts[msg.sender].depositAmount) /
            (depositReceipts[msg.sender].shares +
                withdrawals[msg.sender].shares);
        withdrawals[msg.sender].shares -= shares;
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
    function claimFee(address receiver) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        if (vaultState.performanceFeeAmount + vaultState.managementFeeAmount >
            vaultState.withdrawPoolAmount) {
            IERC20(vaultParams.asset).safeTransfer(msg.sender, vaultState.withdrawPoolAmount);
            return;
        }
        vaultState.withdrawPoolAmount -= (vaultState.performanceFeeAmount + vaultState.managementFeeAmount);
        uint256 claimAmount = vaultState.performanceFeeAmount + vaultState.managementFeeAmount;
        vaultState.performanceFeeAmount = 0;
        vaultState.managementFeeAmount = 0;
        IERC20(vaultParams.asset).safeTransfer(receiver, claimAmount);
    }

    /**
     * @notice close round, collect profit and calculate PPS
     */
    function closeRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        closeEthLPRound();
        closeUsdLPRound();
        closeOptionsRound();
        vaultState.currentRoundFeeAmount = getManagementFee();
        roundPricePerShares[currentRound] = ShareMath.pricePerShare(
            vaultState.totalShares,
            _totalValueLocked() - vaultState.currentRoundFeeAmount,
            vaultParams.decimals
        );
        recalculateAllocateRatio();
        emit RoundClosed(
            currentRound,
            _totalValueLocked(),
            vaultState.currentRoundFeeAmount
        );
        currentRound++;
    }

    function getVaultState() external view returns (VaultState memory) {
        return vaultState;
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
    function getFeeInfo() external view returns (uint256, uint256) {
        return (vaultParams.performanceFeeRate, vaultParams.managementFeeRate);
    }

    /**
     * @notice acquire asset form vendor, prepare funds for withdrawal
     */
    function acquireWithdrawalFunds() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        uint256 withdrawAmountIncludeFee = (roundWithdrawalShares[currentRound - 1] * 
            roundPricePerShares[currentRound - 1]) / 1e6 + vaultState.currentRoundFeeAmount;
        uint256 withdrawEthLPAmount = (withdrawAmountIncludeFee * allocateRatio.ethLPRatio) / 10 ** allocateRatio.decimals;
        uint256 withdrawUsdLPAmount = (withdrawAmountIncludeFee * allocateRatio.usdLPRatio) / 10 ** allocateRatio.decimals;
        uint256 withdrawOptionsAmount = (withdrawAmountIncludeFee * allocateRatio.optionsRatio) / 10 ** allocateRatio.decimals;
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsEthLP(withdrawEthLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdLP(withdrawUsdLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdOptions(withdrawOptionsAmount);
        vaultState.managementFeeAmount += vaultState.currentRoundFeeAmount;
        vaultState.totalShares -= roundWithdrawalShares[currentRound];
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
        uint256 withdrawAmount = (roundWithdrawalShares[currentRound - 1] *
            roundPricePerShares[currentRound - 1]) / 1e6;
        return withdrawAmount + vaultState.currentRoundFeeAmount;
    }

    /**
     * @notice get total value locked vault
     */
    function totalValueLocked() external view returns (uint256) {
        return _totalValueLocked();
    }

    /**
     * @notice Allow admin to settle the covered calls mechanism
     * @param amount the amount in ETH we should sell
     */
    function settleCoveredCalls(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(amount <= getTotalEthLPAssets(), "INVALID_POS_SIZE");
        uint256 usdAmount = acquireWithdrawalFundsEthLP(amount);
        depositToUsdLiquidityStrategy(usdAmount);
        recalculateAllocateRatio();
    }

    /**
     * @notice Allow admin to settle the covered puts mechanism
     * @param amount the amount in usd we should buy eth
     */
    function settleCoveredPuts(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        require(amount <= getTotalUsdLPAssets(), "INVALID_POS_SIZE");
        uint256 usdAmount = acquireWithdrawalFundsUsdLP(amount);
        depositToEthLiquidityStrategy(usdAmount);
        recalculateAllocateRatio();
    }

    /**
     * @notice get total value locked vault
     */
    function _totalValueLocked() private view returns (uint256) {
        return
            vaultState.pendingDepositAmount +
            getTotalEthLPAssets() +
            getTotalUsdLPAssets() +
            getTotalOptionsAmount();
    }

    function allocatedRatio() external view returns (uint256, uint256, uint256) {
        return (
            allocateRatio.ethLPRatio,
            allocateRatio.usdLPRatio,
            allocateRatio.optionsRatio
        );
    }

    /**
     * @notice get the current round number
     */
    function getCurrentRound() external view returns (uint256) {
        return currentRound;
    }
}
