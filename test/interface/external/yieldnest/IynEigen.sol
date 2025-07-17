// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

interface IynEigen {
    function deposit(address asset, uint256 amount, address receiver) external returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);
}
