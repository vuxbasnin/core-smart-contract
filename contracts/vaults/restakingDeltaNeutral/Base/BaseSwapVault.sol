// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../extensions/Uniswap/Uniswap.sol";
import "hardhat/console.sol";

abstract contract BaseSwapVault {
    UniSwap internal swapProxy;
    mapping(address => mapping(address => uint24)) internal fees;

    function baseSwapVault_Initialize(
        address _swapAddress,
        address[] memory _token0s,
        address[] memory _token1s,
        uint24[] memory _fees
    ) internal virtual {
        swapProxy = UniSwap(_swapAddress);

        for (uint8 i = 0; i < _fees.length; i++) {
            fees[_token0s[i]][_token1s[i]] = _fees[i];
        }
    }

    function getFee(address token0, address token1) internal view returns(uint24){
        uint24 fee = fees[token0][token1];
        if(fee == 0) fee = fees[token1][token0];
        
        return fee;
    }
}
