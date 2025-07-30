// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IHooks {
    error InvalidPerformanceFee();
    error CallerNotVault();

    event PerformanceFeeCharged(
        address indexed recipient,
        uint256 sharesMinted,
        uint256 performanceFeeAmount,
        uint256 totalBaseAssetsBefore,
        uint256 totalBaseAssetsAfter
    );
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);
    event SetPerformanceFeeRecipient(address indexed oldRecipient, address indexed newRecipient);

    function performanceFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);

    function afterProcessAccounting(uint256 totalAssetsBefore, uint256 totalAssetsAfter) external;
    function setPerformanceFee(uint256 performanceFee_) external;
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external;
}
