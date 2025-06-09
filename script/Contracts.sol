/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function WETH() external pure returns (address);
    function STETH() external pure returns (address);
    function WSTETH() external pure returns (address);
    function YNETH() external pure returns (address);
    function YNETHX() external pure returns (address);
    function YNLSDE() external pure returns (address);
    function OETH() external pure returns (address);
    function WOETH() external pure returns (address);
    function METH() external pure returns (address);
    function SFRXETH() external pure returns (address);
    function USDC() external pure returns (address);
}

library MainnetContracts {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WOETH = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    address public constant YNETHX = 0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb;
    address public constant YNETH = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
    address public constant YNLSDE = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;

    address public constant SWELL = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public constant TIMELOCK = address(0x0);
    address public constant FACTORY = 0x1756987c66eC529be59D3Ec1edFB005a2F9728E1;
    address public constant PROXY_ADMIN = 0xA02A8DC24171aC161cCb74Ef02C28e3cA2204783;

    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer

    address public constant YNETHX_VIEWER = 0x514d0aC9BFAf631AC7b303564bA1C822bC52F365;

    // EVK Vault eWETH-22 is used as the buffer for ynETHx
    address public constant EULER_WETH_22_VAULT = address(0x45c3B59d53e2e148Aaa6a857521059676D5c0489);

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
    function WETH() external pure override returns (address) {
        return MainnetContracts.WETH;
    }

    function STETH() external pure override returns (address) {
        return MainnetContracts.STETH;
    }

    function WSTETH() external pure override returns (address) {
        return MainnetContracts.WSTETH;
    }

    function YNETH() external pure override returns (address) {
        return MainnetContracts.YNETH;
    }

    function YNETHX() external pure override returns (address) {
        return MainnetContracts.YNETHX;
    }

    function YNLSDE() external pure override returns (address) {
        return MainnetContracts.YNLSDE;
    }

    function OETH() external pure override returns (address) {
        return MainnetContracts.OETH;
    }

    function WOETH() external pure override returns (address) {
        return MainnetContracts.WOETH;
    }

    function METH() external pure override returns (address) {
        return MainnetContracts.METH;
    }

    function SFRXETH() external pure override returns (address) {
        return MainnetContracts.SFRXETH;
    }

    function USDC() external pure override returns (address) {
        return MainnetContracts.USDC;
    }
}
