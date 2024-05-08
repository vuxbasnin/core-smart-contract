// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @title IRestakingPool
 * Interface for Restaking Pool.
 */
interface IRestakingPool {
    /**
     * @notice Deposits a specified amount of tokens into the staking contract.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraws a specified amount of tokens from the staking contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external;
}
