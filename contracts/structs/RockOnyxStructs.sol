// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct VaultParams {
    uint8 decimals;
    address asset;
    uint56 minimumSupply;
    uint104 cap;
}

struct VaultState {
    uint256 totalBalance;
    uint256 totalAssets;
}

struct DepositReceipt {
    uint256 shares;
}

struct Withdrawal {
    uint256 shares;
}