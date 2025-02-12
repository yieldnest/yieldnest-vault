// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
import {AsyncWithdrawalLib} from "src/library/AsyncWithdrawalLib.sol";

contract Withdrawer is BaseWithdrawer {
    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @return baseAssets The amount of base assets in the queue.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual override returns (uint256 baseAssets) {
        return AsyncWithdrawalLib.asyncWithdrawalBalance(asset_);
    }

    /**
     * @notice Returns the requestIds array.
     * @return requestIds The requestIds array.
     */
    function getWOETHRequestIds() external view returns (uint256[] memory requestIds) {
        requestIds = OriginWithdrawalLib.getWOETHRequestIds();
    }

    /**
     * @notice Requests a withdrawal of WOETH.
     * @return requestId the requestId of the WOETH withdrawal.
     * @dev WOETH is a wrapper around OETH. This function will first redeem WOETH for OETH, then request the OETH withdrawal.
     */
    function requestWithdrawalWOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256 requestId) {
        requestId = OriginWithdrawalLib.requestWithdrawalWOETH(amount);
    }

    /**
     * @notice Requests a withdrawal of OETH.
     * @return requestId the requestId of the OETH withdrawal.
     */
    function requestWithdrawalOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256 requestId) {
        requestId = OriginWithdrawalLib.requestWithdrawalOETH(amount);
    }

    /**
     * @notice Claims WOETH withdrawals.
     * @param requestIds the requestIds of the WOETH withdrawals to claim.
     * @return amounts the amounts of WOETH claimed.
     * @return totalAmount the total amount of WOETH claimed.
     */
    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        (amounts, totalAmount) = OriginWithdrawalLib.claimWithdrawalsWOETH(requestIds);
    }
}
