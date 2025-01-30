// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IWithdrawer {
    function asyncWithdrawalBalance(address asset) external view returns (uint256);
}
