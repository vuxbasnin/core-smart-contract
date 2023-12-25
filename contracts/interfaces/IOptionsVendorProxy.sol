// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IOptionsVendorProxy {
    function depositToVendor(address receiver, uint256 amount, address connector) external;
    function withdrawFromVendor(uint256 amount) external;
}
