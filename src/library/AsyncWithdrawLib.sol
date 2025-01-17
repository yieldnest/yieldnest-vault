// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts} from "script/Contracts.sol";

import {VaultLib, IVault} from "src/library/VaultLib.sol";

library AsyncWithdrawLib {
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
        // TODO: handle ynETH and ynLSDe withdrawal queue
        return (0, 0);
    }
}
