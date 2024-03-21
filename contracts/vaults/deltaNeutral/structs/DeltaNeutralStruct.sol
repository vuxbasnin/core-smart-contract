// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct DepositReceipt {
    uint256 shares;
    uint256 depositAmount;
}

struct Withdrawal {
    uint256 shares;
    uint256 pps;
    uint256 profit;
    uint256 performanceFee;
    uint256 withdrawAmount;
}

struct VaultParams {
    uint8 decimals;
    address asset;
    uint256 minimumSupply;
    uint256 cap;
    uint256 performanceFeeRate;
    uint256 managementFeeRate;
}

struct VaultState {
    uint256 performanceFeeAmount;
    uint256 managementFeeAmount;
    uint256 withdrawPoolAmount;
    uint256 pendingDepositAmount;
    uint256 totalShares;
}

struct PerpDexState {
    uint256 unAllocatedBalance;
    uint256 perpDexBalance;
}

struct EthStakeLendState {
    uint256 unAllocatedBalance;
}

struct DeltaNeutralAllocateRatio{
    uint256 ethStakeLendRatio;
    uint256 perpDexRatio;
    uint8 decimals;
}
