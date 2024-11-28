// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IBNBXStakeManagerV2 {
    function convertBnbToBnbX(uint256 amount) external view returns (uint256);
    function convertBnbXToBnb(uint256 amount) external view returns (uint256);
}
