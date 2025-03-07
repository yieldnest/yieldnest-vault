/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// USDC (primary deposit asset)
// USDT
// GHO
// sFRAX
// sUSDe
// USDe
// sUSDS (Maker DAO/Sky)
// scrvUSD


interface IContracts {
    function USDC() external pure returns (address);
    function USDT() external pure returns (address);
    function GHO() external pure returns (address);
    function SFRAX() external pure returns (address);
    function SUSDE() external pure returns (address);
    function USDE() external pure returns (address);
    function SUSDS() external pure returns (address);
    function SCRVUSD() external pure returns (address);
}

library MainnetContracts {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant SFRAX = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32;

    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    address public constant YNUSDx = 0x238213078DbD09f2D15F4c14c02300FA1b2A81BB; // TODO: Update with deployed YnUSDx

    address public constant PROVIDER = 0x56D43f8C6c3891d081AD93B27419c37394857117; // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer

    address public constant YNETHX_VIEWER = 0x514d0aC9BFAf631AC7b303564bA1C822bC52F365;

    // EVK Vault eWETH-22 is used as the buffer for ynETHx
    address public constant EULER_WETH_22_VAULT = address(0x45c3B59d53e2e148Aaa6a857521059676D5c0489);
    address public constant TIMELOCK = 0xb5b52c63067E490982874B0d0F559668Bbe0c36B;

    address public constant PARASWAP_AUGUSTUS_SWAPPER_ROUTER = 0x6A000F20005980200259B80c5102003040001068;

    address public constant CURVE_LP_SCRVUSD_SUSDE_STRATEGY = 0x0000000000000000000000000000000000000000; // TODO: Update with deployed strategy

    address public constant CURVE_LP_SCRVUSD_SUSDE_CONNECTOR = 0x0000000000000000000000000000000000000000; // TODO: Update with deployed connector

    address public constant CURVE_LP_SCRVUSD_SUSDE_POOL = 0xd29f8980852c2c76fC3f6E96a7Aa06E0BedCC1B1; 

    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    // Morpho Gauntlet USDC Vault is used as the buffer for ynUSDCx
    address public constant MORPHO_GAUNTLET_USDC_VAULT = address(0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458);

    address public constant WSTETH_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address public constant YNLSDE_WITHDRAWAL_QUEUE_MANAGER = 0x8Face3283E20b19d98a7a132274B69C1304D60b4;
    address public constant YNLSDE_REDEMPTION_ASSETS_VAULT = 0x73bC33999C34a5126CA19dC900F22690C288D55e;

    address public constant YNETH_WITHDRAWAL_QUEUE_MANAGER = 0x0BC9BC81aD379810B36AD5cC95387112990AA67b;
    address public constant YNETH_REDEMPTION_ASSETS_VAULT = 0x5D6e53c42E3B37f82F693937BC508940769c5caf;

    address public constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;

    address public constant CURVE_REGISTRY = 0x7D86446dDb609eD0F5f8684AcF30380a356b2B4c;

    address public constant CURVE_TWOCRYPTO_FACTORY = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;

    address public constant METH_STAKING_MANAGER = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;

    address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant FRX_ETH_WETH_DUAL_ORACLE = 0x350a9841956D8B0212EAdF5E14a449CA85FAE1C0;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    address public constant CURVE_LP_YNETH_YNLSDE_POOL = 0x1f59cC10c6360DA918B0235c98E58008452816EB;
    address public constant CURVE_LP_YNETH_YNLSDE_CONNECTOR = 0xe66E34F9E3116ce497Cbd15268f175eC711539d5;
    address public constant CURVE_LP_YNETH_YNLSDE_STRATEGY = 0x823976dA34aC45C23a8DfEa51B3Ff1Ae0D980213;

    // Smokehouse WSTETH
    address public constant SMOKEHOUSE_WSTETH = 0x833AdaeF212c5cD3f78906B44bBfb18258F238F0;
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
}
