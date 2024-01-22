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
    uint256 withdrawPoolAmount;
    uint256 pendingDepositAmount;
    uint256 totalShares;
}

struct OptionsStrategyState {
    uint256 allocatedBalance;
    uint256 unAllocatedBalance;
}

struct DepositReceipt {
    uint256 shares;
}

struct Withdrawal {
    uint256 shares;
}

struct DepositState {
    uint256 tokenId;
    uint128 liquidity;
}