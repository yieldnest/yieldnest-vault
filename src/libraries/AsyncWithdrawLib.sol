// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {MainnetContracts} from "script/Contracts.sol";

import {VaultLib, IVault} from "src/libraries/VaultLib.sol";

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
        if (asset_ != MainnetContracts.SLISBNB) {
            return (0, 0);
        }

        // Get total value of pending withdrawals from stake manager
        ISlisBnbStakeManager.WithdrawalRequest[] memory requests =
            ISlisBnbStakeManager(MainnetContracts.SLIS_BNB_STAKE_MANAGER).getUserWithdrawalRequests(address(this));

        uint256 withdrawalValue;
        for (uint256 j; j < requests.length; j++) {
            withdrawalValue += requests[j].amountInSnBnb;
        }

        return (withdrawalValue, VaultLib.convertAssetToBase(asset_, withdrawalValue));
    }
}
