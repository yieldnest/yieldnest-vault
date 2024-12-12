// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vault} from "src/Vault.sol";

contract PublicViewsVault is Vault {
    function convertToAssetsForAsset(address asset_, uint256 shares, Math.Rounding rounding)
        public
        view
        returns (uint256 assets, uint256 baseAssets)
    {
        return _convertToAssets(asset_, shares, rounding);
    }

    function convertToSharesForAsset(address asset_, uint256 assets, Math.Rounding rounding)
        public
        view
        returns (uint256 shares, uint256 baseAssets)
    {
        return _convertToShares(asset_, assets, rounding);
    }

    function convertAssetToBase(address asset_, uint256 assets) public view returns (uint256) {
        return _convertAssetToBase(asset_, assets);
    }

    function convertBaseToAsset(address asset_, uint256 assets) public view returns (uint256) {
        return _convertBaseToAsset(asset_, assets);
    }
}
