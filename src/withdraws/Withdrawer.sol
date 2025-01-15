// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseAsyncWithdrawStrategy} from "src/base/BaseAsyncWithdrawStrategy.sol";

import {AsyncWithdrawLib} from "src/libraries/AsyncWithdrawLib.sol";

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
        return AsyncWithdrawLib.asyncWithdrawBalance(asset_);
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }
}
