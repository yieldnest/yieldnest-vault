// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";

library AsyncWithdrawalLib {
    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view returns (uint256 baseAssets) {
        baseAssets = _asyncWithdrawalBalance(asset_);
    }

    function _asyncWithdrawalBalanceSLISBNB() private view returns (uint256 baseAssets) {
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        ISlisBnbStakeManager.WithdrawalRequest[] memory requests = stakeManager.getUserWithdrawalRequests(address(this));

        if (requests.length == 0) {
            return 0;
        }

        uint256 withdrawalValue;
        for (uint256 j; j < requests.length; j++) {
            withdrawalValue += requests[j].amountInSnBnb;
        }

        baseAssets = stakeManager.convertSnBnbToBnb(withdrawalValue);
    }

    function _asyncWithdrawalBalance(address asset) private view returns (uint256 baseAssets) {
        if (asset == MC.SLISBNB) {
            return _asyncWithdrawalBalanceSLISBNB();
        }

        return 0;
    }
}
