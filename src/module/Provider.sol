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

/*
    The Provider fetches state from other contracts.
*/

contract Provider is IProvider {
    error UnsupportedAsset(address asset);

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

        if (asset == MC.BUFFER || asset == MC.YNETH || asset == MC.WOETH) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.YNLSDE) {
            // ynLSDe does not expose convertToAssets, use previewRedeem instead
            return IynLSDe(asset).previewRedeem(1e18);
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

        if (asset == MC.CURVE_LP_YNETH_YNLSDE_POOL) {
            (int256 lpRate, uint256 updatedAt) = ICurveLpConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR).rate();
            // assert rate is positive
            if (lpRate < 0) {
                revert("Rate is negative");
            }

            // assert recent update
            // if (updatedAt < block.timestamp - 5 hours) {
            //     revert("Rate is stale");
            // }
            // // convert lp rate to ynlsde rate
            // uint256 ynlsdeRate = lpRate * IERC4626(MC.YNLSDE).convertToAssets(1e18) / IERC4626(MC.YNETH).convertToAssets(1e18);

            return uint256(lpRate);
        }

        revert UnsupportedAsset(asset);
    }
}
