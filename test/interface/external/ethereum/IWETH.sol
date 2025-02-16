// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function totalSupply() external view returns (uint256);
    function approve(address guy, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function symbol() external returns (string memory);
}
