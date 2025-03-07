// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IProvider {
    function getRate(address asset) external view returns (uint256);
}

interface ICurveLpConnector {
    function rate() external view returns (int256 rate, uint256 updatedAt);
}
