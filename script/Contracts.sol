/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function USDC() external pure returns (address);
    function USDT() external pure returns (address);
    function GHO() external pure returns (address);
    function SFRAX() external pure returns (address);
    function SUSDE() external pure returns (address);
    function USDE() external pure returns (address);
    function SUSDS() external pure returns (address);
    function SCRVUSD() external pure returns (address);
    function FRAX() external pure returns (address);
    function USDS() external pure returns (address);
    function CRVUSD() external pure returns (address);
    function YNUSDx() external pure returns (address);
}

library MainnetContracts {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant SFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;

    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public constant WRAPPED_USDC = 0xdA7d2025c7f1f1A1d34AB3F4dF01102d0428E574;

    address public constant YNUSDx = 0x3DB228FE836D99Ccb25Ec4dfdC80ED6d2CDdCB4b;

    address public constant TIMELOCK = 0x739711358Ee02d0D6d6eE51D6A07dc862ddB132d;

    address public constant PARASWAP_AUGUSTUS_SWAPPER_ROUTER = 0x6A000F20005980200259B80c5102003040001068;

    // Morpho Gauntlet USDC Vault is used as the buffer for ynUSDCx
    address public constant MORPHO_GAUNTLET_USDC_VAULT = address(0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458);

    address public constant SUPER_USDC_VAULT = 0xF7DE3c70F2db39a188A81052d2f3C8e3e217822a;

    address public constant FXUSD_BASE_POOL_FACET = 0x33636D49FbefBE798e15e7F356E8DBef543CC708;

    address public constant FXSAVE = 0x7743e50F534a7f9F1791DdE7dCD89F7783Eefc39;

    address public constant FXBASE = 0x65C9A641afCEB9C0E6034e558A319488FA0FA3be;

    address public constant FXUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;
}

contract L1Contracts is IContracts {
    function USDC() external pure override returns (address) {
        return MainnetContracts.USDC;
    }

    function USDT() external pure override returns (address) {
        return MainnetContracts.USDT;
    }

    function GHO() external pure override returns (address) {
        return MainnetContracts.GHO;
    }

    function SFRAX() external pure override returns (address) {
        return MainnetContracts.SFRAX;
    }

    function SUSDE() external pure override returns (address) {
        return MainnetContracts.SUSDE;
    }

    function USDE() external pure override returns (address) {
        return MainnetContracts.USDE;
    }

    function SUSDS() external pure override returns (address) {
        return MainnetContracts.SUSDS;
    }

    function SCRVUSD() external pure override returns (address) {
        return MainnetContracts.SCRVUSD;
    }

    function FRAX() external pure override returns (address) {
        return MainnetContracts.FRAX;
    }

    function USDS() external pure override returns (address) {
        return MainnetContracts.USDS;
    }

    function CRVUSD() external pure override returns (address) {
        return MainnetContracts.CRVUSD;
    }

    function YNUSDx() external pure override returns (address) {
        return MainnetContracts.YNUSDx;
    }
}
