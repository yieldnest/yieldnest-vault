// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IFeeModule {
    error InvalidPerformanceFee();
    error CallerNotVault();

    event PerformanceFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 performanceFeeAmount);
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);
    event SetPerformanceFeeRecipient(address indexed oldRecipient, address indexed newRecipient);

    function chargePerformanceFee() external;
    function setPerformanceFee(uint256 performanceFee_) external;
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external;
}
