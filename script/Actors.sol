// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
    function UNAUTHORIZED() external view returns (address);
    function PROPOSER_1() external view returns (address);
    function PROPOSER_2() external view returns (address);
    function EXECUTOR_1() external view returns (address);
    function EXECUTOR_2() external view returns (address);
}

contract LocalActors is IActors {
    address public constant ADMIN = address(1);
    address public constant UNAUTHORIZED = address(3);

    address public constant PROPOSER_1 = address(1);
    address public constant PROPOSER_2 = address(2);

    address public constant EXECUTOR_1 = address(3);
    address public constant EXECUTOR_2 = address(4);
}

contract AnvilActors is IActors {
    address public constant ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant UNAUTHORIZED = address(0);

    address public constant PROPOSER_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant PROPOSER_2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    address public constant EXECUTOR_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant EXECUTOR_2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
}

contract HoleskyActors is IActors {
    address public constant ADMIN = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant UNAUTHORIZED = address(0);

    address public constant PROPOSER_1 = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant PROPOSER_2 = 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39;

    address public constant EXECUTOR_1 = 0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913;
    address public constant EXECUTOR_2 = 0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39;
}

contract ChapelActors is IActors {
    address public constant ADMIN = 0x0c099101d43e9094E4ae9bC2FC38f8b9875c23c5;
    address public constant UNAUTHORIZED = address(0);

    address public constant PROPOSER_1 = 0x9f0A34ccb5ba9C71336F0c8Cd6181205928B8404;
    address public constant PROPOSER_2 = 0x9f0A34ccb5ba9C71336F0c8Cd6181205928B8404;

    address public constant EXECUTOR_1 = 0x9f0A34ccb5ba9C71336F0c8Cd6181205928B8404;
    address public constant EXECUTOR_2 = 0x9f0A34ccb5ba9C71336F0c8Cd6181205928B8404;
}
