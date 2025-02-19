// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IwstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}
