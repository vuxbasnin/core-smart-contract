// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IWithdrawRestakingPool.sol";
import "../../interfaces/IZircuitRestakeProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ZircuitWithdrawRestakingPool is IWithdrawRestakingPool {

    constructor(address _zircuitDepositAddress, IERC20 _stakingToken) {
    }

    function withdraw(uint256 amount) external override {
    }
}