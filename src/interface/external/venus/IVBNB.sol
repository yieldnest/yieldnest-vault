// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVBNB {
    function exchangeRateStored() external view returns (uint256);
    function mint() external payable;
    function redeem(uint256 redeemTokens) external;
}
