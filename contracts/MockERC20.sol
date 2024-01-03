// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStableCoin is ERC20 {

    constructor(string memory token, string memory symbol) ERC20(token, symbol){

        _mint(msg.sender, 1000000000000000000000000);
    }

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}

contract MockETH is ERC20 {

    constructor(string memory token, string memory symbol) ERC20(token, symbol){

        _mint(msg.sender, 1000000000000000000000000);
    }

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}
