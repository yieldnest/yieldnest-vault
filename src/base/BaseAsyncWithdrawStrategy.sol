// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "src/Common.sol";
import {BaseStrategy} from "src/base/BaseStrategy.sol";

/**
 * @title BaseAsyncWithdrawStrategy
 * @author Yieldnest
 * vault.
 */
abstract contract BaseAsyncWithdrawStrategy is BaseStrategy {
    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        // Get base balance from parent contract
        totalBaseBalance = super._computeTotalAssets();

        // Get storage
        AssetStorage storage assetStorage = _getAssetStorage();

        // Iterate through assets
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            (, uint256 balanceInBase) = _asyncWithdrawBalance(assetList[i]);
            totalBaseBalance += balanceInBase;
        }
    }

    /**
     * @notice Internal function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     */
    function _asyncWithdrawBalance(address asset_)
        internal
        view
        virtual
        returns (uint256 balance, uint256 balanceInBase);
}
