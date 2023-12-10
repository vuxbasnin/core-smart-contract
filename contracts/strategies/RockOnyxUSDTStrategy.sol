    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";

interface ILido {
    function submit() external payable returns (uint256);
}

contract RockOnyxUSDTStrategy  {

    ILido LIDO;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(address lidoAddress) {
        LIDO = ILido(lidoAddress);
    }

    /**
     * @notice submit amount to Stake on Lido
     */
    function stakeToVender(uint256 amount) external {
        LIDO.submit{value: amount}();
    }
}