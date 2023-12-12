    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";

contract RockOnyxUSDTVault is RockOnyxAccessControl{
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
    event InitiateWithdraw(address indexed account, uint256 amount, uint256 shares);
    event Withdraw(address indexed account, uint256 amount, uint256 shares);

    constructor(address asset) {
        vaultParams = VaultParams(18, asset, 1000, 1_000_000);
        vaultState = VaultState(0, 0);

        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Mints the vault shares to the creditor
     * @param amount is the amount of `asset` deposited
     * @param creditor is the address to receieve the deposit
     */
    function _depositFor(uint256 amount, address creditor) private returns (uint256) {
        require(vaultState.totalAssets + amount <= vaultParams.cap, "EXCEED_CAP");
        require(amount >= vaultParams.minimumSupply, "INVALID_DEPOSIT_AMOUNT");

        uint256 shares = _issueShares(amount);
        DepositReceipt memory depositReceipt = depositReceipts[creditor];
        depositReceipt.shares += shares;

        vaultState.totalAssets += amount;
        vaultState.totalBalance += amount;

        return shares;
    }

    /**
     * @notice Mints the vault shares to the creditor
     * shares = amount / pricePerShare <=> amount / (vaultState.totalAssets / vaultState.totalBalance)
     */
    function _issueShares(uint256 amount) view  private returns(uint256) {
        if(vaultState.totalAssets <= 0) 
            return amount;

        return amount / (vaultState.totalAssets / vaultState.totalBalance); 
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "INVALID_DEPOSIT_AMOUNT");

        uint256 shares = _depositFor(amount, msg.sender);

        // An approve() by the msg.sender is required beforehand
        IERC20(vaultParams.asset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Deposit(msg.sender, amount, shares);
    }

    /**
     * @notice Initiates a withdrawal that can be processed once the round completes
     * @param numShares is the number of shares to withdraw
     */
    function _initiateWithdraw(uint256 numShares) internal {
        DepositReceipt memory depositReceipt = depositReceipts[msg.sender];

        require(numShares > 0, "INVALID_SHARES");
        require(depositReceipt.shares >= numShares, "INVALID_SHARES");

        Withdrawal storage withdrawal = withdrawals[msg.sender];
        withdrawal.shares += numShares;
    }

    /**
     * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
     */
    function completeWithdraw(address withdrawaler) internal {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        Withdrawal storage withdrawal = withdrawals[withdrawaler];

        // This checks if there is a withdrawal
        require(withdrawal.shares > 0, "NOT_INITIATED");

        // We leave the round number as non-zero to save on gas for subsequent writes
        withdrawal.shares = 0;

        uint256 withdrawAmount =
            ShareMath.sharesToAsset(
                withdrawal.shares,
                vaultState.totalAssets / vaultState.totalBalance,
                vaultParams.decimals
            );

        emit Withdraw(msg.sender, withdrawAmount, withdrawal.shares);

        DepositReceipt memory depositReceipt = depositReceipts[withdrawaler];
        depositReceipt.shares -= withdrawal.shares;

        IERC20(vaultParams.asset).safeTransfer(
            msg.sender,
            withdrawAmount
        );
    }
}