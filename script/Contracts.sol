// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function DEPLOY_FACTORY() external view returns (address);
    function KERNEL_VAULT() external view returns (address);
    function KARAK_VAULT() external view returns (address);
}

contract ChapelContracts {
    address public constant DEPLOY_FACTORY = 0x964C6d4050e052D627b8234CAD9CdF0981E40EB3;
    address public constant KERNEL_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant KARAK_VAULT = 0x0000000000000000000000000000000000000000;
}
