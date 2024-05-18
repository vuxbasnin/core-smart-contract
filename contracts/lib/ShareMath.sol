// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library ShareMath {
    uint256 internal constant PLACEHOLDER_UINT = 1;

    function assetToShares(
        uint256 assetAmount,
        uint256 assetPerShare,
        uint256 decimals
    ) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");

        return (assetAmount * (10 ** decimals)) / (assetPerShare);
    }

    function sharesToAsset(
        uint256 shares,
        uint256 assetPerShare,
        uint256 decimals
    ) internal pure returns (uint256) {
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");

        return (shares * (assetPerShare)) / (10 ** decimals);
    }

    function pricePerShare(
        uint256 totalShares,
        uint256 totalAssets,
        uint256 decimals
    ) internal pure returns (uint256) {
        return
            totalShares > 0
                ? (totalAssets * (10 ** decimals)) / totalShares
                : (10 ** decimals);
    }
}
