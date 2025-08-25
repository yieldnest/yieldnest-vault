// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
}
