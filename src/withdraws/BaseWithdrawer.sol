// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {VaultLib} from "src/library/VaultLib.sol";
import {IVault} from "src/interface/IVault.sol";

abstract contract BaseWithdrawer is BaseStrategy {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
        _initialize(admin, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Internal function to compute the total assets. Must handle the assets that are in queue for withdrawal.
     * @dev This function should return the amount in base denomination.
     */
    function computeTotalAssets() public view override returns (uint256 totalBaseBalance) {
        totalBaseBalance = super.computeTotalAssets();

        // Get storage
        IVault.AssetStorage storage assetStorage = VaultLib.getAssetStorage();

        // Iterate through assets
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            totalBaseBalance += asyncWithdrawalBalance(assetList[i]);
        }
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual returns (uint256 baseAssets);
}
