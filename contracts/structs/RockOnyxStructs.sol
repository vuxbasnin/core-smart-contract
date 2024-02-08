// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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
    uint256 currentRoundFeeAmount;
    uint256 withdrawPoolAmount;
    uint256 pendingDepositAmount;
    uint256 totalShares;
    uint256 lastLockedAmount;
}

struct OptionsStrategyState {
    uint256 allocatedUsdceBalance;
    uint256 unAllocatedUsdcBalance;
    uint256 unsettledProfit;
    uint256 unsettledLoss;
}

struct DepositReceipt {
    uint256 shares;
    uint256 depositAmount;
}

struct Withdrawal {
    uint256 shares;
    uint256 round;
}

struct EthLPState {
    uint256 tokenId;
    uint128 liquidity;
    int24 lowerTick;
    int24 upperTick;
    uint256 unAllocatedBalance;
}

struct UsdLPState {
    uint256 tokenId;
    uint128 liquidity;
    int24 lowerTick;
    int24 upperTick;
    uint256 unAllocatedUsdcBalance;
    uint256 unAllocatedUsdceBalance;
}

struct AllocateRatio{
    uint256 ethLPRatio;
    uint256 usdLPRatio;
    uint256 optionsRatio;
    uint8 decimals;
}