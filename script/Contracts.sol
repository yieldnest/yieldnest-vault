// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MainnetContracts {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant YNETH = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
}

contract ChapelContracts {
    address public constant ACTORS = 0xbA02225f0fdB684c80ad1e829FC31f048c416Ce6;
    address public constant VAULT_FACTORY = 0x964C6d4050e052D627b8234CAD9CdF0981E40EB3;
    address public constant SINGLE_VAULT = 0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c;
    address public constant KERNEL_VAULT = address(0);
    address public constant KARAK_KslisBNB = address(0);
    address public constant KARAK_SUPERVISOR = address(0);
    address public constant slisBNB = 0x80815ee920Bd9d856562633C36D3eB0E43cb15e2;
}

contract BscContracts {
    address public constant ACTORS = 0x1AA714a271047fA5AAFD190F084b66aA77Ba3562;
    address public constant VAULT_FACTORY = 0xf6B9b69B7e13D37D3846698bA2625e404C7586aF;
    address public constant SINGLE_VAULT = 0x40020796C11750975aD8758a1F2ab725f6b72Db2;
    address public constant KERNEL_VAULT = address(0);
    address public constant KARAK_KslisBNB = 0x8529019503c5BD707d8Eb98C5C87bF5237F89135;
    address public constant KARAK_VAULT_SUPERVISOR = 0x4a2b015CcB8658998692Db9eD4522B8e846962eD;
    address public constant slisBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant ListaStakeManager = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
}
