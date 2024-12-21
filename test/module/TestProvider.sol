// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IBNBXStakeManagerV2} from "src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";

/*
    The Provider fetches state from other contracts.
*/

contract TestProvider is IProvider {
    error UnsupportedAsset(address asset);

    function getRate(address asset) external view override returns (uint256) {
        if (asset == MC.BUFFER || asset == MC.YNBNBK) {
            return IERC4626(asset).previewRedeem(1e18);
        }

        if (asset == MC.WBNB) {
            return 1e18;
        }

        if (asset == MC.BNBX) {
            return IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18);
        }

        if (asset == MC.SLISBNB) {
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(1e18);
        }

        revert UnsupportedAsset(asset);
    }
}
