// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";

library TestHelpers {
    function getActiveAssets(IVault vault) public view returns (address[] memory) {
        // Get all assets and filter for active ones
        address[] memory allAssets = vault.getAssets();
        address[] memory activeAssets = new address[](allAssets.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < allAssets.length; i++) {
            IVault.AssetParams memory assetInfo = vault.getAsset(allAssets[i]);
            if (assetInfo.active) {
                activeAssets[activeCount] = allAssets[i];
                activeCount++;
            }
        }

        // Resize the array to the actual number of active assets
        assembly {
            mstore(activeAssets, activeCount)
        }

        return activeAssets;
    }
}
