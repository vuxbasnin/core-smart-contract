// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";

contract BaseProxy is ReentrancyGuard, RockOnyxAccessControl {
    constructor() {
        _grantRole(ROCK_ONYX_ADMIN_ROLE, msg.sender);
    }

    function withdraw(address receiver, address tokenAddress, uint256 amount) public nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        IERC20 token = IERC20(tokenAddress);
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance in contract");

        bool sent = token.transfer(receiver, amount);
        require(sent, "Token transfer failed");
    }
}
