// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";

library AsyncWithdrawLib {
    event SetWithdrawalQueueManager(address asset, address withdrawalQueueManager);

    struct WithdrawerStorage {
        mapping(address => address) withdrawalQueueManagers;
    }

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
            (, uint256 balanceInBase) = asyncWithdrawBalance(assetList[i], address(this));
            totalBaseBalance += balanceInBase;
        }
    }

    function getWithdrawalQueueManager(address asset) public view returns (address) {
        return getWithdrawerStorage().withdrawalQueueManagers[asset];
    }

    function setWithdrawalQueueManager(address asset, address withdrawalQueueManager) public {
        getWithdrawerStorage().withdrawalQueueManagers[asset] = withdrawalQueueManager;
        emit SetWithdrawalQueueManager(asset, withdrawalQueueManager);
    }

    function isAsyncAsset(address asset) public view returns (bool) {
        return getWithdrawerStorage().withdrawalQueueManagers[asset] != address(0);
    }

    /**
     * @notice Retrieves the strategy storage struct.
     * @return $ The strategy storage struct.
     */
    function getWithdrawerStorage() public pure returns (WithdrawerStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.withdrawer")
            $.slot := 0x4d9d8592a06949b5317dec0d2ac80ab3d5da773e7c912c33d931056d30e36843
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawBalance(address asset_, address owner)
        public
        view
        returns (uint256 assets, uint256 baseAssets)
    {
        assets = getQueuedAssets(asset_, owner);
        baseAssets = VaultLib.convertAssetToBase(asset_, assets);
    }

    function getQueuedAssets(address asset, address owner) public view returns (uint256 assets) {
        if (!isAsyncAsset(asset)) {
            return 0;
        }

        // TODO: handle other assets here
        if (asset == MC.YNLSDE || asset == MC.YNETH) {
            IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(getWithdrawalQueueManager(asset));
            (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) =
                queueManager.withdrawalRequestsForOwner(owner);
            for (uint256 i = 0; i < requests.length; i++) {
                if (!requests[i].processed) {
                    assets += requests[i].amount;
                }
            }
            return assets;
        }

        revert UnsupportedAsset(asset);
    }
}
