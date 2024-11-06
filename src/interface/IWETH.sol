// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "src/Common.sol";

interface IWETH is IERC20 {
    // Deposit ETH and receive WETH
    function deposit() external payable;

    // Withdraw ETH and burn WETH
    function withdraw(uint256 amount) external;

    // Fallback function to handle direct ETH transfers
    receive() external payable;
}
