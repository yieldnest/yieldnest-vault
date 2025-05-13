// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {TestnetContracts as TC} from "script/Contracts.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IVault} from "src/interface/IVault.sol";

/*
    The Provider fetches state from other contracts.
*/

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

contract TestProvider is IProvider {
    error UnsupportedAsset(address asset);

    function isClisBnbStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return (
                keccak256(bytes(version)) == keccak256(bytes("0.1.0"))
                    || keccak256(bytes(version)) == keccak256(bytes("0.2.0"))
            ) && vaultAsset == TC.SLISBNB;
        } catch {
            return false;
        }
    }

    function getRate(address asset) external view override returns (uint256) {
        // support only ynWBNBK for now
        // if (asset == TC.YNWBNBK || asset == TC.YNBNBK || asset == TC.YNCLISBNBK) {
        if (asset == TC.YNWBNBK) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == TC.WBNB) {
            return 1e18;
        }

        if (asset == TC.BNBX) {
            return 1e18;
        }

        if (asset == TC.SLISBNB) {
            return 1e18;
        }

        if (isClisBnbStrategyVault(asset)) {
            // base asset to clisBnbStrategy is SlisBnb
            uint256 slisBnbPerShare = IERC4626(asset).convertToAssets(1e18);
            // converts slisBnbPerShare to bnb
            return ISlisBnbStakeManager(TC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(slisBnbPerShare);
        }

        revert UnsupportedAsset(asset);
    }
}
