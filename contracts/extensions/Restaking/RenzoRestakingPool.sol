// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../interfaces/IRestakingPool.sol";
import "../../interfaces/IRenzoRestakeProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RenzoRestakingPool is IRestakingPool {
    using SafeERC20 for IERC20;

    IERC20 private stakingToken;
    address private renzoDepositAddress;
    IRenzoRestakeProxy private renzoRestakeProxy;

    constructor(address _renzoDepositAddress, IERC20 _stakingToken) {
        renzoDepositAddress = _renzoDepositAddress;
        stakingToken = _stakingToken;
        renzoRestakeProxy = IRenzoRestakeProxy(_renzoDepositAddress);
    }

    function deposit(uint256 amount) external {
        stakingToken.approve(address(this), amount);

        renzoRestakeProxy.depositETH{value: amount}();
    }

    function withdraw(uint256 amount) external {
    }
}