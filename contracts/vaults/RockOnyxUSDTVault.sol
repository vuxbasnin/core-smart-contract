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
    event RoundClosed(int256 pnl);

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
        vaultParams = VaultParams(6, _usdc, 10_000_000, 1_000_000 * 10 ** 6);
        vaultState = VaultState(0, 0);

        options_Initialize(_optionsVendorProxy, _optionsReceiver, _usdce, _usdc, _swapProxy);
        ethLP_Initialize( _vendorLiquidityProxy, _vendorNftPositionddress, _swapProxy, _usdc, _weth, _wstEth);
        usdLP_Initialize(_vendorLiquidityProxy, _vendorNftPositionddress, _swapProxy, _usdc, _usdce);
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
        uint256 depositToEthLPAmount = (vaultState
            .pendingDepositAmount * 60) / 100;
        uint256 depositToOptionStrategyAmount = (vaultState
            .pendingDepositAmount * 20) / 100;
        uint256 depositToCashAmount = (vaultState.pendingDepositAmount * 20) /
             100;
        
        depositToEthLiquidityStrategy(depositToEthLPAmount);
        depositToUsdLiquidityStrategy(depositToCashAmount);
        depositToOptionsStrategy(depositToOptionStrategyAmount);

        vaultState.pendingDepositAmount = 0;
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param numShares is the number of shares to withdraw
     */
    function initiateWithdrawal(uint256 numShares) external nonReentrant {
        DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        require(depositReceipt.shares >= numShares, "INVALID_SHARES");

        Withdrawal storage withdrawal = roundWithdrawals[currentRound][msg.sender];
        withdrawal.shares += numShares;
        depositReceipt.shares -= numShares;
        
        roundWithdrawalShares[currentRound] += numShares;
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     */
    function completeWithdrawal(uint256 round, uint256 shares) external nonReentrant {
        Withdrawal storage withdrawal = roundWithdrawals[round][msg.sender];
        require(withdrawal.shares > shares, "INVALID_SHARES");

        uint256 withdrawAmount = ShareMath.sharesToAsset(
            shares,
            roundPricePerShares[round],
            vaultParams.decimals
        );

        require(vaultState.withdrawPoolAmount > withdrawAmount, "EXCEED_WITHDRAW_POOL_CAPACITY");

        withdrawal.shares -= shares;
        vaultState.withdrawPoolAmount -= withdrawAmount;

        IERC20(vaultParams.asset).safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, withdrawal.shares);
    }

    function closeRound() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        closeEthLPRound();
        closeUsdLPRound();
        // closeUsdOptionsRound();

        roundPricePerShares[currentRound] = pricePerShare();
        currentRound++;
    }

    function acquireWithdrawalFunds() external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        uint256 withdrawAmount = roundWithdrawalShares[currentRound] * roundPricePerShares[currentRound];
        uint256 withdrawEthLPAmount = (withdrawAmount * 60) / 100;
        uint256 withdrawUsdLPAmount = (withdrawAmount * 20) / 100;
        uint256 withdrawUsdOptionsAmount = (withdrawAmount * 20) / 100;
        
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsEthLP(withdrawEthLPAmount);
        vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdLP(withdrawUsdLPAmount);
        // vaultState.withdrawPoolAmount += acquireWithdrawalFundsUsdOptions(withdrawUsdOptionsAmount);
    }

    function balanceOf(address account) external view returns (uint256) {
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

        return
            vaultState.pendingDepositAmount +
            getTotalOptionsAmount() +
            getTotalEthLPAssets() +
            getTotalUsdLPAssets();
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
