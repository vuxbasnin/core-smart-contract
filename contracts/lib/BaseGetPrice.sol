// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../extensions/TransferHelper.sol";
import "../interfaces/IGetPriceProxy.sol";
import "../interfaces/IUniswapV3Pool.sol";

contract BaseGetPrice is IGetPriceProxy {
    uint8 constant USDC_DECIMALS = 6;
    uint8 constant ETH_DECIMALS = 18;

    address usdcEthPoolAddress;
    address ethWstEthPoolAddress;
    
    constructor(address _usdcEthPoolAddress, address _ethWstEthPoolAddress) {
        usdcEthPoolAddress = _usdcEthPoolAddress;
        ethWstEthPoolAddress = _ethWstEthPoolAddress;
    }

    function getEthPrice() public view returns (uint256 price) {
        return getPriceOf(usdcEthPoolAddress, USDC_DECIMALS, ETH_DECIMALS);
    }

    function getWstEthPrice() external view returns (uint256 price) {
        return getEthPrice() * getEthWstEthPrice();
    }

    function getEthWstEthPrice() private view returns (uint256 price) {
        return getPriceOf(ethWstEthPoolAddress, ETH_DECIMALS, ETH_DECIMALS);
    }

    function getPriceOf(address poolAddress, uint8 token1Decimals, uint8 token2Decimals) private view returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        return sqrtPriceX96ToPrice(sqrtPriceX96, token1Decimals, token2Decimals);
    }

    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 token1Decimals, uint8 token2Decimals) private pure returns(uint256){
        return sqrtPriceX96 ** 2 * 10 ** (token1Decimals - token2Decimals) /  2 ** 192;
    }
}