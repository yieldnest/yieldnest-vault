// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IWithdrawalQueue {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    struct WithdrawalRequest {
        uint128 cumulativeStETH;
        uint128 cumulativeShares;
        address owner;
        uint40 timestamp;
        bool claimed;
        uint40 reportTimestamp;
    }

    function FINALIZE_ROLE() external view returns (bytes32);

    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestsIds);

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;

    function getLastFinalizedRequestId() external view returns (uint256);

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
}
