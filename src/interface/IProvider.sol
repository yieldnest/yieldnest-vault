// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IProvider {
    function getRate(address asset) external view returns (uint256);
    function otherAssets(address vault, address strategy) external view returns (uint256 assets);
}
