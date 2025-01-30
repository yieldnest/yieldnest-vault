// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {AsyncWithdrawalLib} from "src/library/AsyncWithdrawalLib.sol";

contract Withdrawer is BaseWithdrawer {
    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual override returns (uint256) {
        return AsyncWithdrawalLib.asyncWithdrawalBalance(asset_);
    }
}
