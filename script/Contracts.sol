// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MainnetContracts {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant YNETH = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
    address public constant YNLSDE = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;
    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public constant ETH_RATE_PROVIDER = address(123456789); // TODO: Update with deployed RateProvider
}
