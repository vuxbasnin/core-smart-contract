// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../Base/BaseDeltaNeutralVault.sol";
import "./strategies/RenzoZircuitRestakingStrategy.sol";
import "./../Base/strategies/PerpDexStrategy.sol";
import "./../structs/RestakingDeltaNeutralStruct.sol";

contract RenzoRestakingDeltaNeutralVault is
    RenzoZircuitRestakingStrategy,
    PerpDexStrategy,
    BaseDeltaNeutralVault
{
    constructor(
        address _usdc,
        address _weth,
        address _swapProxy,
        address _perpDexAddress,
        address _perpDexReceiver,
        address _perpDexConnector,
        address _restakingToken,
        uint256 _initialPPS,
        address[] memory _stakingProxies,
        uint24[] memory _fees
    )
        RenzoZircuitRestakingStrategy()
        PerpDexStrategy()
        BaseDeltaNeutralVault(_usdc, _initialPPS)
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);
        ethRestaking_Initialize(_restakingToken, _swapProxy, _usdc, _weth, _stakingProxies, _fees);
        perpDex_Initialize(_perpDexAddress, _perpDexReceiver, _usdc, _perpDexConnector);
        initialPPS = _initialPPS;
    }

    /**
     * @notice allocate assets to strategies
     */
    function allocateAssets() internal override {
        uint256 depositToRestakingAmount = vaultState.pendingDepositAmount / 2;
        uint256 depositToPerpDexAmount = vaultState.pendingDepositAmount - depositToRestakingAmount;
        vaultState.pendingDepositAmount = 0;

        depositToRestakingStrategy(depositToRestakingAmount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    function rebalanceAsset(uint256 amount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if (getTotalRestakingTvl() > getTotalPerpDexAssets()) {
            transferAssetToPerpDex(amount);
            return;
        }

        transferAssetToEthSpot(amount);
    }

    /**
     * @notice acquire asset, prepare funds for withdrawal
     */
    function acquireWithdrawalFunds(uint256 usdAmount) external nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        require(usdAmount <= _totalValueLocked(), "INVALID_ACQUIRE_AMOUNT");
        uint256 totalRestakingPerpDexBalance = getTotalRestakingTvl() + getTotalPerpDexAssets();
        uint256 ethStakeLendRatio =  getTotalRestakingTvl() * 1e4 / totalRestakingPerpDexBalance;
        uint256 perpDexRatio =  getTotalPerpDexAssets() * 1e4 / totalRestakingPerpDexBalance;
        uint256 ethStakeLendAmount = usdAmount * ethStakeLendRatio / 1e4;
        uint256 perpDexAmount = usdAmount * perpDexRatio / 1e4;
        vaultState.withdrawPoolAmount += acquireFundsFromRestakingStrategy(ethStakeLendAmount);
        vaultState.withdrawPoolAmount += acquireFundsFromPerpDex(perpDexAmount);
    }

    /**
     * @notice Allow admin to transfer asset to Restaking Strategy for rebalance
     * @param amount the amount in usd we should buy eth
     */
    function transferAssetToEthSpot(uint256 amount) internal {
        require(amount <= getTotalPerpDexAssets(), "INVALID_TRANSFER_AMOUNT");
        uint256 depositAmount = acquireFundsFromPerpDex(amount);
        depositToPerpDexStrategy(depositAmount);
    }

    /**
     * @notice Allow admin to transfer asset to Perpetual Strategy for rebalance
     * @param amount the amount in usd we should buy eth
     */
    function transferAssetToPerpDex(uint256 amount) internal {
        require(amount <= getTotalRestakingTvl(), "INVALID_TRANSFER_AMOUNT");
        uint256 depositToPerpDexAmount = acquireFundsFromRestakingStrategy(
            amount
        );
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    function syncBalance(uint256 perpDexbalance) external nonReentrant {
        _auth(ROCK_ONYX_OPTIONS_TRADER_ROLE);

        syncRestakingBalance();
        syncPerpDexBalance(perpDexbalance);
    }

    /**
     * @notice get total value locked vault
     */
    function _totalValueLocked() internal view override returns (uint256) {
        return
            vaultState.pendingDepositAmount +
            getTotalRestakingTvl() +
            getTotalPerpDexAssets();
    }

    /**
     * Migration
     */
    function exportVaultState()
        external
        view
        returns (
            DepositReceiptArr[] memory,
            WithdrawalArr[] memory,
            VaultParams memory,
            VaultState memory,
            EthRestakingState memory,
            PerpDexState memory
        )
    {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        return (
            depositReceiptArr,
            withdrawalArr,
            vaultParams,
            vaultState,
            restakingStratState,
            perpDexState
        );
    }

    function importVaultState(
        DepositReceiptArr[] calldata _depositReceiptArr,
        WithdrawalArr[] calldata _withdrawalArr,
        VaultParams calldata _vaultParams,
        VaultState calldata _vaultState,
        EthRestakingState calldata _ethRestakingState,
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
        restakingStratState = _ethRestakingState;
        perpDexState = _perpDexState;
    }
}
