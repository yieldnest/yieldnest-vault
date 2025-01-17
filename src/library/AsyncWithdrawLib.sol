// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

library AsyncWithdrawLib {
    error UnsupportedAsset(address asset);
    /**
     * @notice Internal function to compute the total assets. Must handle the assets that are in queue for withdrawal.
     * @dev This function should return the amount in base denomination.
     */

    function computeTotalAssets() public view returns (uint256 totalBaseBalance) {
        totalBaseBalance = VaultLib.computeTotalAssets();

        // Get storage
        IVault.AssetStorage storage assetStorage = VaultLib.getAssetStorage();

        // Iterate through assets
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            (, uint256 balanceInBase) = asyncWithdrawBalance(assetList[i]);
            totalBaseBalance += balanceInBase;
        }
    }

    /**
     * @notice Internal function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawBalance(address asset_) public view returns (uint256 assets, uint256 baseAssets) {
        assets = getAssets(asset_);
        baseAssets = VaultLib.convertAssetToBase(asset_, assets);
    }

    function getAssets(address asset) public pure returns (uint256 assets) {
        if (asset == MC.WETH) {
            return 0;
        }

        if (asset == MC.BUFFER) {
            return 0;
        }

        if (asset == MC.STETH) {
            return 0;
        }

        if (asset == MC.WBTC) {
            return 0;
        }

        if (asset == MC.METH) {
            return 0;
        }

        // TODO: handle other assets here
        revert UnsupportedAsset(asset);
    }
}
