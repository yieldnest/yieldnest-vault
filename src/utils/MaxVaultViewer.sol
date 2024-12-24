// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {IERC20Metadata, AccessControlUpgradeable} from "src/Common.sol";
import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";

contract MaxVaultViewer is BaseVaultViewer, AccessControlUpgradeable {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    error ZeroAddress();
    error InvalidAssets();
    error InvalidAssetAdd(address);
    error InvalidAssetRemove(address);

    event AddUnderlyingAsset(address indexed asset);
    event RemoveUnderlyingAsset(address indexed asset);

    struct AssetStorage {
        mapping(address => bool) underlyingAssets;
        uint256 underlyingAssetsLength;
    }

    function initialize(address vault_, address admin_) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _getViewerStorage().vault = vault_;
    }

    function getStrategies() public view returns (AssetInfo[] memory) {
        IVault vault = IVault(_getViewerStorage().vault);

        address[] memory assets = vault.getAssets();
        uint256 assetsLength = assets.length;

        uint256 underlyingAssetsLength = _getAssetStorage().underlyingAssetsLength;
        if (assetsLength <= underlyingAssetsLength) revert InvalidAssets();

        uint256 strategiesLength = assetsLength - underlyingAssetsLength;

        address[] memory strategies = new address[](strategiesLength);
        uint256[] memory balances = new uint256[](strategiesLength);

        uint256 j = 0;
        for (uint256 i = 0; i < assetsLength; ++i) {
            if (!isUnderlyingAsset(assets[i])) {
                strategies[j] = assets[i];
                balances[j] = IERC20Metadata(assets[i]).balanceOf(address(vault));
                j++;
            }
        }

        return _getAssetsInfo(strategies, balances);
    }

    /**
     * @notice Internal function to get the asset storage.
     * @return $ The asset storage.
     */
    function _getAssetStorage() internal pure returns (AssetStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.asset")
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }

    modifier onlyVaultAsset(address asset_) {
        IVault vault = IVault(_getViewerStorage().vault);
        address[] memory underlyingAssets = vault.getAssets();

        bool found;
        for (uint256 i = 0; i < underlyingAssets.length; ++i) {
            if (underlyingAssets[i] == asset_) {
                found = true;
            }
        }

        if (!found) revert InvalidAssetAdd(asset_);
        _;
    }

    function addUnderlyingAssets(address[] calldata underlyingAssets) external onlyRole(UPDATER_ROLE) {
        for (uint256 i = 0; i < underlyingAssets.length; ++i) {
            _addUnderlyingAsset(underlyingAssets[i]);
        }
    }

    function removeUnderlyingAssets(address[] calldata underlyingAssets) external onlyRole(UPDATER_ROLE) {
        for (uint256 i = 0; i < underlyingAssets.length; ++i) {
            _removeUnderlyingAsset(underlyingAssets[i]);
        }
    }

    function isUnderlyingAsset(address asset_) public view returns (bool) {
        return _getAssetStorage().underlyingAssets[asset_];
    }

    function getUnderlyingAssetsLength() external view returns (uint256) {
        return _getAssetStorage().underlyingAssetsLength;
    }

    function _addUnderlyingAsset(address asset_) internal onlyVaultAsset(asset_) {
        if (asset_ == address(0)) revert ZeroAddress();
        if (_getAssetStorage().underlyingAssets[asset_]) revert InvalidAssetAdd(asset_);

        _getAssetStorage().underlyingAssets[asset_] = true;
        _getAssetStorage().underlyingAssetsLength += 1;

        emit AddUnderlyingAsset(asset_);
    }

    function _removeUnderlyingAsset(address asset_) internal {
        if (asset_ == address(0)) revert ZeroAddress();
        if (!_getAssetStorage().underlyingAssets[asset_]) revert InvalidAssetRemove(asset_);

        _getAssetStorage().underlyingAssets[asset_] = false;
        _getAssetStorage().underlyingAssetsLength -= 1;

        emit RemoveUnderlyingAsset(asset_);
    }
}
