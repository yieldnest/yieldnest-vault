// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IOETHVault {
    function requestWithdrawal(uint256 _amount) external returns (uint256 requestId, uint256 queued);
    function claimWithdrawals(uint256[] memory _requestIds)
        external
        returns (uint256[] memory amounts, uint256 totalAmount);
    function claimWithdrawal(uint256 _requestId) external returns (uint256 amount);

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 timestamp; // timestamp of the withdrawal request
        // Amount of oTokens to redeem. eg OETH
        uint128 amount;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint128 queued;
    }

    function withdrawalRequests(uint256 _index) external view returns (WithdrawalRequest memory);
}
