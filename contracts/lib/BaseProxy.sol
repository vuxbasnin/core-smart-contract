// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../extensions/RockOnyxAccessControl.sol";

contract BaseProxy is ReentrancyGuard, RockOnyxAccessControl {
    IERC20 public token;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    function withdraw(address receiver, uint256 amount) public nonReentrant {
        _auth(ROCK_ONYX_ADMIN_ROLE);
        
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance in contract");

        bool sent = token.transfer(receiver, amount);
        require(sent, "Token transfer failed");
    }
}
