// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct PerpDexState {
    uint256 unAllocatedBalance;
    uint256 unsettledProfit;
    uint256 unsettledLoss;
}

struct EthStakeLendState {
    uint256 unAllocatedBalance;
}

struct DeltaNeutralAllocateRatio{
    uint256 ethStakeLendRatio;
    uint256 perpDexRatio;
    uint8 decimals;
}