    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../lib/ShareMath.sol";
import "../interfaces/IPriceFeedProxy.sol";
import "../interfaces/ISwapProxy.sol";
import "../interfaces/ILido.sol";
import "../extensions/RockOnyxAccessControl.sol";
import "../extensions/RockOnyxSwap.sol";
import "../oracles/PriceFeedOracle.sol";

contract RockOnyxUSDTStrategy is RockOnyxAccessControl, PriceFeedOracle, RockOnyxSwap{
    ILido LIDO;

    /************************************************
     *  EVENTS
     ***********************************************/

    constructor(address lidoAddress, address priceFeed, address swapAddress) PriceFeedOracle(priceFeed) RockOnyxSwap(swapAddress){
        LIDO = ILido(lidoAddress);
    }

    /**
     * @notice submit amount to Stake on Lido
     */
    function stakeToVender(uint256 amount) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        LIDO.submit{value: amount}();
    }

    function swapToEth(uint256 amount) external {
        _auth(ROCK_ONYX_ADMIN_ROLE);

        swapProxy.swap(amount);
    }
}