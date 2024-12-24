// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {TestnetContracts as TC} from "script/Contracts.sol";

/*
    The Provider fetches state from other contracts.
*/

contract TestProvider is IProvider {
    error UnsupportedAsset(address asset);

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

        revert UnsupportedAsset(asset);
    }
}
