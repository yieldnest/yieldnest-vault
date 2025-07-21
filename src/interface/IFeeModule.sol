// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IFeeModule {
    error InvalidPerformanceFee();
    error CallerNotVault();

    function chargePerformanceFee() external;
    function setPerformanceFee(uint256 performanceFee_) external;
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external;
}
