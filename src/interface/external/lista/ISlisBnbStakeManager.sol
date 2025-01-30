// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ISlisBnbStakeManager {
    struct WithdrawalRequest {
        uint256 uuid;
        uint256 amountInSnBnb;
        uint256 startTime;
    }

    function BOT() external view returns (bytes32);

    function deposit() external payable;

    function claimUndelegated(address _validator) external returns (uint256 _uuid, uint256 _amount);

    function convertBnbToSnBnb(uint256 _amount) external view returns (uint256);

    function convertSnBnbToBnb(uint256 _amountInSlisBnb) external view returns (uint256);

    function getUserWithdrawalRequests(address _address) external view returns (WithdrawalRequest[] memory);

    function requestWithdraw(uint256 _amountInSnBnb) external;

    function claimWithdraw(uint256 _idx) external;

    function getUserRequestStatus(address _user, uint256 _idx)
        external
        view
        returns (bool _isClaimable, uint256 _amount);

    function whitelistValidator(address _address) external;

    function unbondingBnb() external view returns (uint256);

    function undelegateFrom(address _operator, uint256 _amount) external returns (uint256);

    function getAmountToUndelegate() external view returns (uint256);

    function reserveAmount() external view returns (uint256);
}
