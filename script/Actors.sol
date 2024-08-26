// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract LocalActors {
    address public constant ADMIN = address(1);
    address public constant OPERATOR = address(2);
    address public constant UNAUTHORIZED = address(3);

    address public constant PROPOSER_1 = address(1);
    address public constant PROPOSER_2 = address(2);

    address public constant EXECUTOR_1 = address(3);
    address public constant EXECUTOR_2 = address(4);
}
