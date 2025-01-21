// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";

library AsyncWithdrawalLib {
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
            uint256 balanceInBase = asyncWithdrawalBalance(assetList[i], address(this));
            totalBaseBalance += balanceInBase;
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_, address owner) public view returns (uint256 baseAssets) {
        baseAssets = _asyncWithdrawalBalance(asset_, owner);
    }

    function _asyncWithdrawalBalanceYN(address queueManager_, address owner)
        private
        view
        returns (uint256 baseAssets)
    {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) = queueManager.withdrawalRequestsForOwner(owner);
        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].processed) {
                // NOTE: needs to be fixed - assumes no slashing for now, as in reality eigenlayer slashing is not active yet
                // also we do not account for the fees here
                baseAssets += requests[i].amount * requests[i].redemptionRateAtRequestTime / 1e18;
            }
        }
        return baseAssets;
    }

    function _asyncWithdrawalBalance(address asset, address owner) private view returns (uint256 baseAssets) {
        // TODO: support WOETH
        if (asset == MC.WOETH) {
            return OriginWithdrawalLib._asyncWithdrawalBalanceWOETH();
        }

        if (asset == MC.WSTETH) {
            IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
            uint256[] memory requestIds = queue.getWithdrawalRequests(owner);
            IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(requestIds);
            for (uint256 i = 0; i < statuses.length; i++) {
                baseAssets += statuses[i].amountOfStETH;
            }
            return baseAssets;
        }

        if (asset == MC.YNETH) {
            return _asyncWithdrawalBalanceYN(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, owner);
        }

        if (asset == MC.YNLSDE) {
            return _asyncWithdrawalBalanceYN(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, owner);
        }

        return 0;
    }
}
