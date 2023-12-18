// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../extensions/RockOnyxAccessControl.sol";

contract RockOnyxOptiontrategy is RockOnyxAccessControl, ReentrancyGuard{
    address venderAddress;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(address _venderAddress){
        venderAddress = _venderAddress;
    }

    /**
     * @notice submit amount to Stake on Lido
     */
    function depositToVender(uint256 amount) external nonReentrant{
        _auth(ROCK_ONYX_ADMIN_ROLE);

        console.log(amount);
    }
    
}