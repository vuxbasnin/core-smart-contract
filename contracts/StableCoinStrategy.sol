// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract StableCoinStrategy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public immutable asset;
    uint256 private _totalSupply;
    uint256 private _cap;
    uint256 private _totalBalance;
    address private _stakingVendor;
    uint256 constant decimals = 18;

    mapping(address => uint256) private balances;

    event Deposit(address indexed account, uint256 amount, uint256 shares);
    event Withdraw(address indexed account, uint256 amount);

    constructor(address _asset, uint256 cap) {
        require(_asset != address(0), "Invalid asset address");
        asset = _asset;
        _totalBalance = 0;
        _cap = cap;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot deposit 0");
        uint256 currentSharePrice = pricePerShare();

        uint256 sharesToMint;
        if (_totalSupply == 0) {
            // Initial share price is 1:1
            sharesToMint = amount;
        } else {
            // Calculate the number of shares based on the current share price
            sharesToMint = (amount * (10 ** decimals)) / currentSharePrice;
        }

        require(sharesToMint > 0, "Shares must be greater than 0");
        balances[msg.sender] += sharesToMint;
        _totalSupply += sharesToMint;
        _totalBalance += amount;

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount, sharesToMint);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");

        uint256 sharesToBurn = (amount * (10 ** decimals)) / pricePerShare();
        require(sharesToBurn > 0, "Insufficient shares");
        require(balances[msg.sender] >= sharesToBurn, "Insufficient balance");
        require(_totalBalance >= amount, "Insufficient vault balance");

        balances[msg.sender] -= sharesToBurn;
        _totalBalance -= amount;

        IERC20(asset).transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function pricePerShare() public view returns (uint256) {
        if (_totalSupply == 0) return 0;

        return (_totalBalance * (10 ** decimals)) / _totalSupply;
    }

    function rebalance(uint256 amount) external nonReentrant {
        // split 60% Staking, 20% cash, 20% options aevo
        // stake lido
        // if yield reward for 8 days based on totalBalance and lido APR > gas fee:
        // stake all ETH to lido
        // otherwise keep options position size for coverred call
        // wrap stETH -> wstETH
        // deposit wstETH to Radiant
        // deposit aevo
        // bridge usdt/usdc arbitrum
        // swap usdt/usdc -> usdc.e
        // transfer USDC.E to Aave
    }

    function withdrawFromStaking(uint152 amount) external nonReentrant {
        // if Call options possible to hit the strike
        //
    }

    function closeRound() external nonReentrant {
        _checkOwner();

        // update _totalBalance update from Staking, Options

        // check options positions
        // if price > strike:  Call Options
        // wrap ETH -> USDC

        // Put Options
        //
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function totalBalance() public view returns (uint256) {
        return _totalBalance;
    }
}
