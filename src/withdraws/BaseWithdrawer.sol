// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";

abstract contract BaseWithdrawer is BaseStrategy {
    /**
     * @notice Initializes the strategy.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param countNativeAsset_ Whether the vault should count the native asset.
     * @param alwaysComputeTotalAssets_ Whether the vault should always compute total assets.
     * @param defaultAssetIndex_ The index of the default asset in the asset list.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external virtual initializer {
        _initialize(
            admin, name, symbol, decimals_, true, countNativeAsset_, alwaysComputeTotalAssets_, defaultAssetIndex_
        );
    }

    /**
     * @notice Returns the fee on raw assets where the fee would get added on top of the assets.
     * @return The fee on raw assets.
     */
    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the fee on total assets where the fee is already included.
     * @return The fee on total assets.
     */
    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Internal function to compute the total assets. Must handle the assets that are in queue for withdrawal.
     * @return totalBaseBalance The total assets in base units.
     * @dev This function should return the amount in base units.
     */
    function computeTotalAssets() public view override returns (uint256 totalBaseBalance) {
        totalBaseBalance = super.computeTotalAssets();

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
     * @notice function to returns the amount of assets in base units that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @return baseAssets The amount of assets in base units.
     * @dev This function should return the amount in base units.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual returns (uint256 baseAssets);
}
