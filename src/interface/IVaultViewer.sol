// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20Metadata} from "src/Common.sol";

library ERC20Viewer {
    function symbol(IERC20Metadata token) internal view returns (string memory) {
        try token.symbol() returns (string memory s) {
            return s;
        } catch {
            return "";
        }
    }

    function name(IERC20Metadata token) internal view returns (string memory) {
        try token.name() returns (string memory n) {
            return n;
        } catch {
            return "";
        }
    }

    function decimals(IERC20Metadata token) internal view returns (uint8) {
        try token.decimals() returns (uint8 d) {
            return d;
        } catch {
            return 0;
        }
    }
}

interface IVaultViewer {
    struct AssetInfo {
        address asset;
        string name;
        string symbol;
        uint256 rate;
        uint256 ratioOfTotalAssets;
        uint256 totalBalanceInUnitOfAccount;
        uint256 totalBalanceInAsset;
        bool canDeposit;
        uint8 decimals;
    }

    struct ViewerStorage {
        address vault;
    }

    /**
     * @notice Retrieves information about all assets in the system
     * @dev This function fetches asset data from the vault and computes various metrics for each asset
     * @return assetsInfo An array of AssetInfo structs containing detailed information about each asset
     */
    function getAssets() external view returns (AssetInfo[] memory assetsInfo);

    function getUnderlyingAssets() external view returns (AssetInfo[] memory assetsInfo);

    function getRate() external view returns (uint256);

    function getVault() external view returns (address);
}
