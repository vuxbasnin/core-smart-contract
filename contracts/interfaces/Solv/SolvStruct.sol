// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct UserDepositSolv {
    address owner;
    bytes32 poolId;
    uint256[] tokenId;
    uint256 currentcyAmount;
    uint256 openFundShareId;
}
