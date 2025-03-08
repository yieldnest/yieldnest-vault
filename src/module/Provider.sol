// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
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

    function isUSDStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return keccak256(bytes(version)) == keccak256(bytes("0.1.0")) && vaultAsset == MC.USDC;
        } catch {
            return false;
        }
    }

    function getRate(address asset) public view virtual returns (uint256) {

        if (asset == MC.USDC) {
            return 1e18;
        }

        if (asset == MC.USDT) {
            return 1e18;
        }

        if (asset == MC.GHO) {
            return 1e18;
        }

        if (asset == MC.USDE) {
            return 1e18;
        }

        if (asset == MC.SFRAX || asset == MC.SUSDE || asset == MC.SUSDS || asset == MC.SCRVUSD) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.MORPHO_GAUNTLET_USDC_VAULT) {
            return IERC4626(asset).convertToAssets(1e18) * 1e12;
        }

        // buffer strategy
        if (isUSDStrategyVault(asset)) {
            return IERC4626(asset).convertToAssets(1e18) * 1e12;
        }

        revert UnsupportedAsset(asset);
    }
}
