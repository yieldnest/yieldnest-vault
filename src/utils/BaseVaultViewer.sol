// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20Metadata, Initializable, Math} from "src/Common.sol";
import {ERC20Viewer, IVaultViewer} from "src/interface/IVaultViewer.sol";

contract BaseVaultViewer is Initializable, IVaultViewer {
    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 private constant DECIMALS = 1_000_000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(address vault_) external initializer {
        getViewerStorage().vault = vault_;
    }

    /**
     * @notice Retrieves information about all assets in the system
     * @dev This function fetches asset data from the vault and computes various metrics for each asset
     * @return assetsInfo An array of AssetInfo structs containing detailed information about each asset
     */
    function getAssets() external view returns (AssetInfo[] memory assetsInfo) {
        return _getAssets();
    }

    function getUnderlyingAssets() external view virtual returns (AssetInfo[] memory assetsInfo) {
        return _getAssets();
    }

    function _getAssets() internal view returns (AssetInfo[] memory assetsInfo) {
        IVault vault = IVault(getViewerStorage().vault);

        address[] memory assets = vault.getAssets();
        uint256[] memory balances = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; ++i) {
            balances[i] = IERC20Metadata(assets[i]).balanceOf(address(vault));
        }

        return _getAssetsInfo(assets, balances);
    }

    function _getAssetsInfo(address[] memory assets, uint256[] memory balances)
        internal
        view
        returns (AssetInfo[] memory assetsInfo)
    {
        IVault vault = IVault(getViewerStorage().vault);
        IProvider rateProvider = IProvider(vault.provider());
        uint256 totalAssets = vault.totalAssets();

        assetsInfo = new AssetInfo[](assets.length);

        for (uint256 i = 0; i < assets.length; ++i) {
            IVault.AssetParams memory assetParams = vault.getAsset(assets[i]);
            uint256 rate = rateProvider.getRate(assets[i]);
            IERC20Metadata asset = IERC20Metadata(assets[i]);

            uint256 assetBalance = balances[i];
            uint256 baseBalance = Math.mulDiv(assetBalance, rate, 10 ** assetParams.decimals, Math.Rounding.Floor);

            assetsInfo[i] = AssetInfo({
                asset: assets[i],
                name: ERC20Viewer.name(asset),
                symbol: ERC20Viewer.symbol(asset),
                rate: rate,
                ratioOfTotalAssets: (baseBalance > 0 && totalAssets > 0) ? baseBalance * DECIMALS / totalAssets : 0,
                totalBalanceInUnitOfAccount: baseBalance,
                totalBalanceInAsset: assetBalance,
                canDeposit: assetParams.active,
                decimals: assetParams.decimals
            });
        }
        return assetsInfo;
    }

    function getRate() external view returns (uint256) {
        IVault vault = IVault(getViewerStorage().vault);
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 decimals = vault.decimals();
        uint256 baseAssetValue = 10 ** decimals;
        if (totalSupply == 0 || totalAssets == 0) return baseAssetValue;
        return Math.mulDiv(baseAssetValue, totalAssets, totalSupply);
    }

    function getVault() external view returns (address) {
        return address(getViewerStorage().vault);
    }

    /**
     * @notice Internal function to get the storage.
     * @return $ The storage.
     */
    function getViewerStorage() internal pure virtual returns (ViewerStorage storage $) {
        assembly {
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }
}
