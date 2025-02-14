// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IOETHVault {
    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 timestamp;
        uint128 amount;
        uint128 queued;
    }

    struct WithdrawalQueueMetadata {
        uint128 queued;
        uint128 claimable;
        uint128 claimed;
        uint128 nextWithdrawalIndex;
    }

    function requestWithdrawal(uint256 _amount) external returns (uint256 requestId, uint256 queued);
    function claimWithdrawals(uint256[] memory _requestIds)
        external
        returns (uint256[] memory amounts, uint256 totalAmount);
    function claimWithdrawal(uint256 _requestId) external returns (uint256 amount);

    function withdrawalRequests(uint256 _index) external view returns (WithdrawalRequest memory);
    function withdrawalQueueMetadata() external view returns (WithdrawalQueueMetadata memory);
    function withdrawalClaimDelay() external view returns (uint256);
    function governor() external view returns (address);
    function setMaxSupplyDiff(uint256 _maxSupplyDiff) external;
    function mint(address _asset, uint256 _amount, uint256 _minimumOusdAmount) external;
}
