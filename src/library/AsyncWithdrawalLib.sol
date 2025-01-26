// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";

library AsyncWithdrawalLib {
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
            totalBaseBalance += asyncWithdrawalBalance(assetList[i]);
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view returns (uint256 baseAssets) {
        baseAssets = _asyncWithdrawalBalance(asset_);
    }

    function _asyncWithdrawalBalanceYNAsset(address queueManager_, address asset_)
        private
        view
        returns (uint256 baseAssets)
    {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) =
            queueManager.withdrawalRequestsForOwner(address(this));

        uint256 decimals = 10 ** VaultLib.getAssetStorage().assets[asset_].decimals;

        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].processed) {
                // NOTE: needs to be fixed - assumes no slashing for now,
                // as in reality eigenlayer slashing is not active yet
                uint256 baseAmount = requests[i].amount * requests[i].redemptionRateAtRequestTime / decimals;
                uint256 fee = baseAmount * requests[i].feeAtRequestTime / 1000000;
                baseAssets += baseAmount - fee;
            }
        }
        return baseAssets;
    }

    function _asyncWithdrawalBalanceWSTETH() private view returns (uint256 baseAssets) {
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
        uint256[] memory requestIds = queue.getWithdrawalRequests(address(this));
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(requestIds);
        for (uint256 i = 0; i < statuses.length; i++) {
            baseAssets += statuses[i].amountOfStETH;
        }
    }

    function _asyncWithdrawalBalance(address asset) private view returns (uint256 baseAssets) {
        if (asset == MC.WOETH) {
            return OriginWithdrawalLib._asyncWithdrawalBalanceWOETH();
        }

        if (asset == MC.WSTETH) {
            return _asyncWithdrawalBalanceWSTETH();
        }

        if (asset == MC.YNETH) {
            return _asyncWithdrawalBalanceYNAsset(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, MC.YNETH);
        }

        if (asset == MC.YNLSDE) {
            return _asyncWithdrawalBalanceYNAsset(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, MC.YNLSDE);
        }

        return 0;
    }
}
