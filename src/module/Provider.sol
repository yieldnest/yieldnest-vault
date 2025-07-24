// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    IProvider,
    IStETH,
    IMETH,
    IsfrxETH,
    IRETH,
    IswETH,
    IFrxEthWethDualOracle,
    IynLSDe,
    ICurveLpConnector
} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";

/*
    The Provider fetches state from other contracts.
*/

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

contract Provider is IProvider {
    error UnsupportedAsset(address asset);
    error RateIsNegative();

    function isETHStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return (
                keccak256(bytes(version)) == keccak256(bytes("0.1.0"))
                    || keccak256(bytes(version)) == keccak256(bytes("0.2.0"))
            ) && vaultAsset == MC.WETH;
        } catch {
            return false;
        }
    }

    function getRate(address asset) public view virtual returns (uint256) {
        if (asset == MC.WETH) {
            return 1e18;
        }

        if (asset == MC.STETH) {
            return 1e18;
        }

        if (asset == MC.OETH) {
            return 1e18;
        }

        if (
            asset == MC.BUFFER || asset == MC.MORPHO_MEV_CAPITAL_WETH || asset == MC.YNETH || asset == MC.WOETH
                || asset == MC.EULER_WETH_22_VAULT
        ) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.YNLSDE) {
            // ynLSDe does not expose convertToAssets, use previewRedeem instead
            return IynLSDe(asset).previewRedeem(1e18);
        }

        if (asset == MC.SMOKEHOUSE_WSTETH) {
            return IStETH(MC.STETH).getPooledEthByShares(IERC4626(asset).convertToAssets(1e18));
        }

        if (asset == MC.WSTETH) {
            return IStETH(MC.STETH).getPooledEthByShares(1e18);
        }

        if (asset == MC.METH) {
            return IMETH(MC.METH_STAKING_MANAGER).mETHToETH(1e18);
        }

        if (asset == MC.RETH) {
            return IRETH(MC.RETH).getExchangeRate();
        }

        if (asset == MC.SWELL) {
            return IswETH(MC.SWELL).swETHToETHRate();
        }

        if (asset == MC.SFRXETH) {
            /* 
            
            The deposit asset for sfrxETH is frxETH and not ETH. 
            In order to account for any frxETH/ETH rate fluctuations,
            an frxETH/ETH oracle is used as provided by Frax.

            Documentation: https://docs.frax.finance/frax-oracle/advanced-concepts
            */
            uint256 frxETHPriceInETH = IFrxEthWethDualOracle(MC.FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
            return IsfrxETH(MC.SFRXETH).pricePerShare() * frxETHPriceInETH / 1e18;
        }

        if (asset == MC.CURVE_LP_YNETH_YNLSDE_STRATEGY) {
            (int256 strategyRate,) = ICurveLpConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR).rate();
            if (strategyRate < 0) {
                revert RateIsNegative();
            }

            return uint256(strategyRate);
        }

        if (isETHStrategyVault(asset)) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        revert UnsupportedAsset(asset);
    }
}
