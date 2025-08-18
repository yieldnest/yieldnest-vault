// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

interface IFeeHooks {
    error InvalidPerformanceFee();
    error InvalidPerformanceFeeRecipient();

    event PerformanceFeeCharged(
        address indexed recipient,
        uint256 sharesMinted,
        uint256 performanceFeeAmount,
        uint256 totalBaseAssetsBefore,
        uint256 totalBaseAssetsAfter,
        uint256 totalShares
    );
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);
    event SetPerformanceFeeRecipient(address indexed oldRecipient, address indexed newRecipient);
    event WithdrawFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 fees, uint256 assets);
    event RedeemFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 shares);

    function performanceFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);

    function setPerformanceFee(uint256 performanceFee_) external;
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external;
}
