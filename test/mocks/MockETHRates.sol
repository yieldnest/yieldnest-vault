// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MockETHRates {

    constructor() {}

    function getRate(address asset) external pure returns (uint256) {
        require(asset != address(0), "no asset");
        return 1e18; // WETH is 1:1 with ETH
    }
}
