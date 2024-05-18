// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @title IRestakingPool
 * Interface for Restaking Pool.
 */
interface IWithdrawRestakingPool {
    /**
     * @notice Withdraws a specified amount of tokens from the staking contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address token, uint256 amount) external;
}
