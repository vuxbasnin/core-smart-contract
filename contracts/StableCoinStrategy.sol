// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract StableCoinStrategy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 constant singleShare = 10 ** 18;
    uint256 internal constant PLACEHOLDER_UINT = 1;

    address public immutable asset;
    uint256 public totalSupply;
    uint256 public totalBalance;
    uint256 private _cap;
    address private _stakingVendor;

    mapping(address => uint256) private balances;

    event Deposit(address indexed account, uint256 amount, uint256 shares);
    event Withdraw(address indexed account, uint256 amount);

    constructor(address _asset, uint256 cap) {
        require(_asset != address(0), "Invalid asset address");
        asset = _asset;
        _cap = cap;
    }

    function initialize(
        address _owner
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit amount must be greater than zero");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        uint256 shares = assetToShares(amount, pricePerShare());

        totalSupply += shares;
        totalBalance += amount;
        balances[msg.sender] += shares;

        emit Deposit(msg.sender, amount, shares);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Withdrawal amount must be greater than zero");
        uint256 currentPricePerShare = pricePerShare();
        uint256 shares = assetToShares(amount, currentPricePerShare);
        require(balances[msg.sender] >= shares, "Insufficient balance");

        totalSupply -= shares;
        totalBalance -= amount;
        balances[msg.sender] -= shares;

        IERC20(asset).transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function pricePerShare() public view returns (uint256) {
        if (totalSupply == 0) return singleShare;
        return (totalBalance * singleShare) / totalSupply;
    }

    function sharesToAsset(
        uint256 shares,
        uint256 assetPerShare
    ) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");

        return (shares * assetPerShare) / singleShare;
    }

    function assetToShares(
        uint256 assetAmount,
        uint256 assetPerShare
    ) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");
        return (assetAmount * singleShare) / assetPerShare;
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

    function closeRound(int256 profitOrLoss) external nonReentrant {
        _checkOwner();

        if (profitOrLoss > 0) {
            totalBalance += uint256(profitOrLoss);
        } else {
            totalBalance -= uint256(-profitOrLoss);
        }

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
}
