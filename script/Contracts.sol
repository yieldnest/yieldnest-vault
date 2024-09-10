// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function ACTORS() external view returns (address);
    function DEPLOY_FACTORY() external view returns (address);
    function SINGLE_VAULT() external view returns (address);
    function KERNEL_VAULT() external view returns (address);
    function KARAK_VAULT() external view returns (address);
    function silsBNB() external view returns (address);
}

contract ChapelContracts {
    address public constant ACTORS = 0xbA02225f0fdB684c80ad1e829FC31f048c416Ce6;
    address public constant VAULT_FACTORY = 0x964C6d4050e052D627b8234CAD9CdF0981E40EB3;
    address public constant SINGLE_VAULT = 0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c;
    address public constant KERNEL_VAULT = address(0);
    address public constant KARAK_VAULT = address(0);
    address public constant silsBNB = 0x80815ee920Bd9d856562633C36D3eB0E43cb15e2;
}

contract BscContracts {
    address public constant ACTORS = 0x1AA714a271047fA5AAFD190F084b66aA77Ba3562;
    address public constant VAULT_FACTORY = 0xf6B9b69B7e13D37D3846698bA2625e404C7586aF;
    address public constant SINGLE_VAULT = 0x40020796C11750975aD8758a1F2ab725f6b72Db2;
    address public constant KERNEL_VAULT = address(0);
    address public constant KARAK_KsilsBNB = 0x8529019503c5BD707d8Eb98C5C87bF5237F89135;
    address public constant silsBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
}
