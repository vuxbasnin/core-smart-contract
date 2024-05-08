// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../deltaNeutral/RockOnyxDeltaNeutralVault.sol";
import "../deltaNeutral/strategies/RockOynxPerpDexStrategy.sol";
import "../deltaNeutral/BaseDeltaNeutralVault.sol";
import "./strategies/RenzoZircuitRestakingStrategy.sol";
import "./structs/RestakingDeltaNeutralStruct.sol";

contract RestakingDeltaNeutralVault is
    RenzoZircuitRestakingStrategy,
    RockOynxPerpDexStrategy,
    BaseDeltaNeutralVault
{
    // Storage for the addresses of the staking proxies and their corresponding points
    mapping(address => uint256) public userPoints; // Maps user addresses to their reward points

    // Event to log points distribution
    event PointsDistributed(address indexed user, uint256 points);

    constructor(
        address _usdc,
        address _weth,
        address _swapProxy,
        address _perpDexProxy,
        address _perpDexReceiver,
        address _restakingToken,
        uint256 _initialPPS,
        address[] memory _stakingProxies
    )
        RenzoZircuitRestakingStrategy()
        RockOynxPerpDexStrategy()
        BaseDeltaNeutralVault(_usdc, _initialPPS)
    {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);

        ethRestaking_Initialize(
            _restakingToken,
            _swapProxy,
            _usdc,
            _weth,
            _stakingProxies
        );
        perpDex_Initialize(_perpDexProxy, _perpDexReceiver, _usdc);

        initialPPS = _initialPPS;
    }

    /**
     * @notice allocate assets to strategies
     */
    function allocateAssets() internal override {
        uint256 depositToEthStakeLendAmount = (vaultState.pendingDepositAmount *
            allocateRatio.ethStakeLendRatio) / 10 ** allocateRatio.decimals;
        uint256 depositToPerpDexAmount = vaultState.pendingDepositAmount -
            depositToEthStakeLendAmount;
        vaultState.pendingDepositAmount = 0;

        depositToRestakingStrategy(depositToEthStakeLendAmount);
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    function rebalanceAsset(uint256 amount) external override nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        if (getTotalRestakingTvl() > getTotalPerpDexAssets()) {
            transferAssetToPerpDex(amount);
            return;
        }

        transferAssetToEthSpot(amount);
    }

    /**
     * @notice Allow admin to transfer asset to Restaking Strategy for rebalance
     * @param amount the amount in usd we should buy eth
     */
    function transferAssetToEthSpot(uint256 amount) internal override {
        require(amount <= getTotalPerpDexAssets(), "INVALID_TRANSFER_AMOUNT");
        uint256 depositAmount = acquireFundsFromPerpDex(amount);
        depositToPerpDexStrategy(depositAmount);
    }

    /**
     * @notice Allow admin to transfer asset to Perpetual Strategy for rebalance
     * @param amount the amount in usd we should buy eth
     */
    function transferAssetToPerpDex(uint256 amount) internal override {
        require(amount <= getTotalRestakingTvl(), "INVALID_TRANSFER_AMOUNT");
        uint256 depositToPerpDexAmount = acquireFundsFromRestakingStrategy(
            amount
        );
        depositToPerpDexStrategy(depositToPerpDexAmount);
    }

    /**
     * @notice recalculate allocate ratio vault
     */
    function recalculateAllocateRatio() internal override {
        uint256 totalEthAssets = getTotalRestakingTvl();
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
            DeltaNeutralAllocateRatio memory,
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
            allocateRatio,
            restakingStratState,
            perpDexState
        );
    }

    function importVaultState(
        DepositReceiptArr[] calldata _depositReceiptArr,
        WithdrawalArr[] calldata _withdrawalArr,
        VaultParams calldata _vaultParams,
        VaultState calldata _vaultState,
        DeltaNeutralAllocateRatio calldata _allocateRatio,
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
        allocateRatio = _allocateRatio;
        restakingStratState = _ethRestakingState;
        perpDexState = _perpDexState;
    }
}
