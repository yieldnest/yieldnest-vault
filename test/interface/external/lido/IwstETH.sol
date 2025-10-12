// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IwstETH {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function wrap(uint256 _stETHAmount) external returns (uint256);

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    function stEthPerToken() external view returns (uint256);

    function stETH() external view returns (address);
}
