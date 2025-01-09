// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ISlisBnbStakeManager {
    struct WithdrawalRequest {
        uint256 uuid;
        uint256 amountInSnBnb;
        uint256 startTime;
    }

    function deposit() external payable;

    function convertBnbToSnBnb(uint256 _amount) external view returns (uint256);

    function convertSnBnbToBnb(uint256 _amountInSlisBnb) external view returns (uint256);

    function getUserWithdrawalRequests(address _address) external view returns (WithdrawalRequest[] memory);
}
