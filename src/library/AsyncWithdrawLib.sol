// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";

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
            (, uint256 balanceInBase) = asyncWithdrawBalance(assetList[i], address(this));
            totalBaseBalance += balanceInBase;
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

    function getAssetsQueuedForWithdrawal(address queueManager_, address owner) public view returns (uint256 assets) {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) = queueManager.withdrawalRequestsForOwner(owner);
        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].processed) {
                assets += requests[i].amount;
            }
        }
        return assets;
    }

    function getQueuedAssets(address asset, address owner) public view returns (uint256 assets) {
        // TODO: support WOETH

        if (asset == MC.WSTETH) {
            IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WQ);
            uint256[] memory requestIds = queue.getWithdrawalRequests(owner);
            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(requestIds);
            for (uint256 i = 0; i < statuses.length; i++) {
                assets += statuses[i].amountOfShares;
            }
            return assets;
        }

        if (asset == MC.YNETH) {
            return getAssetsQueuedForWithdrawal(MC.YNETH_WQM, owner);
        }

        if (asset == MC.YNLSDE) {
            return getAssetsQueuedForWithdrawal(MC.YNLSDE_WQM, owner);
        }

        return 0;
    }
}
