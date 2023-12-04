// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./extensions/Permissions.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract StableCoinStrategy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    IERC20 public asset;
    uint256 public cap;

    mapping(address => uint256) private balances;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor(address _asset, uint256 _cap) {
        require(_asset != address(0), "Invalid asset address");
        asset = IERC20(_asset);
        cap = _cap;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot deposit 0");
        uint256 vaultBalance = asset.balanceOf(address(this));
        require(vaultBalance + amount <= cap, "Cap exceeded");

        balances[msg.sender] += amount;
        asset.transferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        asset.transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }
}
