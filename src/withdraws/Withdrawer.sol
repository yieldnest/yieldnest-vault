// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {MainnetContracts} from "script/Contracts.sol";

import {BaseAsyncWithdrawStrategy} from "src/base/BaseAsyncWithdrawStrategy.sol";

contract Withdrawer is BaseAsyncWithdrawStrategy {
    /**
     * @notice Internal function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function _asyncWithdrawBalance(address asset_)
        internal
        view
        override
        returns (uint256 assets, uint256 baseAssets)
    {
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

        return (withdrawalValue, _convertAssetToBase(asset_, withdrawalValue));
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }
}
