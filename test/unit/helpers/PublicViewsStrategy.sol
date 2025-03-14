// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseStrategy} from "src/strategy/BaseStrategy.sol";

contract PublicViewsStrategy is BaseStrategy {
    function convertToAssetsForAsset(address asset_, uint256 shares, Math.Rounding rounding)
        public
        view
        returns (uint256 assets, uint256 baseAssets)
    {
        return _convertToAssets(asset_, shares, rounding);
    }

    function convertToSharesForAsset(address asset_, uint256 assets, Math.Rounding rounding)
        public
        view
        returns (uint256 shares, uint256 baseAssets)
    {
        return _convertToShares(asset_, assets, rounding);
    }

    function convertAssetToBase(address asset_, uint256 assets) public view returns (uint256) {
        return _convertAssetToBase(asset_, assets);
    }

    function convertBaseToAsset(address asset_, uint256 assets) public view returns (uint256) {
        return _convertBaseToAsset(asset_, assets);
    }

    /**
     * @notice Returns the fee on raw assets where the fee would get added on top of the assets.
     * @return The fee on raw assets.
     */
    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the fee on total assets where the fee is already included.
     * @return The fee on total assets.
     */
    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param countNativeAsset_ Whether the vault should count the native asset.
     * @param alwaysComputeTotalAssets_ Whether the vault should always compute total assets.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
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
}
