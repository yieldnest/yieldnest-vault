// solhint-disable one-contract-per-file
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20Metadata, Initializable, Math} from "src/Common.sol";

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

contract BaseVaultViewer is Initializable {
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

    struct Storage {
        IVault vault;
    }

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

    function initialize(IVault vault_) external initializer {
        _getStorage().vault = vault_;
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
        IVault vault = IVault(_getStorage().vault);

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
        IVault vault = IVault(_getStorage().vault);
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
        IVault vault = IVault(_getStorage().vault);
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 decimals = vault.decimals();
        uint256 baseAssetValue = 10 ** decimals;
        if (totalSupply == 0 || totalAssets == 0) return baseAssetValue;
        return Math.mulDiv(baseAssetValue, totalAssets, totalSupply);
    }

    function getVault() external view returns (address) {
        return address(_getStorage().vault);
    }

    /**
     * @notice Internal function to get the storage.
     * @return $ The storage.
     */
    function _getStorage() internal pure virtual returns (Storage storage $) {
        assembly {
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }
}
