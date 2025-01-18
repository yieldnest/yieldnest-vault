// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "lib/yieldnest-protocol/src/interfaces/IWithdrawalQueueManager.sol";
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
     * @notice Retrieves the strategy storage struct.
     * @return $ The strategy storage struct.
     */
    function getBaseStrategyStorage() public pure returns (BaseStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.base")
            $.slot := 0x5cfdf694cb3bdee9e4b3d9c4b43849916bf3f018805254a1c0e500548c668500
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawBalance(address asset_, address owner) public view returns (uint256 assets, uint256 baseAssets) {
        assets = getAssets(asset_, owner);
        baseAssets = VaultLib.convertAssetToBase(asset_, assets);
    }

    function getAssets(address asset, address owner) public pure returns (uint256 assets) {
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
        if (asset == MC.YNLSDE) {
            uint256 balance = IWithdrawalQueueManager(MC.YNLSDE_WM).getWithdrawableBalance(owner);
            uint256 fee = IWithdrawalQueueManager(MC.YNLSDE_WM).calculateWithdrawalFee(balance);
            return balance - fee;
        }

        if (asset == MC.YNETH) {
            uint256 balance = IWithdrawalQueueManager(MC.YNETH_WM).getWithdrawableBalance(owner);
            uint256 fee = IWithdrawalQueueManager(MC.YNETH_WM).calculateWithdrawalFee(balance);
            return balance - fee;
        }

        revert UnsupportedAsset(asset);
    }
}
