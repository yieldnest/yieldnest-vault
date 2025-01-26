// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
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

    function getWOETHRequestIds() external view returns (uint256[] memory) {
        return OriginWithdrawalLib.getWOETHRequestIds();
    }

    function requestWithdrawalWOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256) {
        return OriginWithdrawalLib.requestWithdrawalWOETH(amount);
    }

    function requestWithdrawalOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256) {
        return OriginWithdrawalLib.requestWithdrawalOETH(amount);
    }

    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        return OriginWithdrawalLib.claimWithdrawalsWOETH(requestIds);
    }
}
