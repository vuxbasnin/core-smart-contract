// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IRestakingPool.sol";
import "../../interfaces/IZircuitRestakeProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ZircuitRestakingPool is IRestakingPool {
    using SafeERC20 for IERC20;

    IERC20 private stakingToken;
    address private zircuitDepositAddress;
    IZircuitRestakeProxy private zircuitRestakeProxy;

    constructor(address _zircuitDepositAddress, IERC20 _stakingToken) {
        zircuitDepositAddress = _zircuitDepositAddress;
        stakingToken = _stakingToken;
        zircuitRestakeProxy = IZircuitRestakeProxy(zircuitDepositAddress);
    }

    function deposit(uint256 amount) external override {
        stakingToken.approve(zircuitDepositAddress, amount);

        zircuitRestakeProxy.depositFor(address(stakingToken), address(this), amount);
    }

    function withdraw(uint256 amount) external override {
    }
}