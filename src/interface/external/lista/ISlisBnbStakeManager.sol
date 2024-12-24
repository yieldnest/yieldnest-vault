// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ISlisBnbStakeManager {
    function convertSnBnbToBnb(uint256 amount) external view returns (uint256);
    function convertBnbToSnBnb(uint256 amount) external view returns (uint256);

    function deposit() external payable;
}
