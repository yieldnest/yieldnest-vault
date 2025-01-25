// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {IVault, VaultLib} from "src/library/VaultLib.sol";

abstract contract BaseWithdrawer is BaseStrategy {
    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    function computeTotalAssets() public view virtual override returns (uint256 totalBaseBalance) {
        totalBaseBalance = VaultLib.computeTotalAssets();

        // Get storage
        IVault.AssetStorage storage assetStorage = VaultLib.getAssetStorage();

        // Iterate through assets
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            totalBaseBalance += asyncWithdrawalBalance(assetList[i]);
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual returns (uint256 baseAssets);
}
