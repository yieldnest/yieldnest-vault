// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {IRateProvider} from "src/interface/IRateProvider.sol";
import {Math, ERC20Upgradeable} from "src/Common.sol";

library Storage {
    using Math for uint256;

    function getVaultStorage() internal pure returns (IVault.VaultStorage storage $) {
        assembly {
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }

    function getAssetStorage() internal pure returns (IVault.AssetStorage storage $) {
        assembly {
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }

    function getStrategyStorage() internal pure returns (IVault.StrategyStorage storage $) {   
        assembly {
            $.slot := 0x36e313fea70c5f83d23dd12fc41865566e392cbac4c21baf7972d39f7af1774d
        }
    }

    function getERC20Storage() internal pure returns (ERC20Upgradeable.ERC20Storage storage $) {
        assembly {
            $.slot := 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00
        }
    }

    function getBaseAsset() internal view returns (address) {
        IVault.AssetStorage storage assetStorage = getAssetStorage();
        return address(assetStorage.list[0]);
    }

    function getTotalAssets() internal view returns (uint256) {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();
        return vaultStorage.totalAssets;
    }

    function getRateProvider() internal view returns (address) {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();
        return vaultStorage.rateProvider;
    }

    function getPaused() internal view returns (bool) {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();
        return vaultStorage.paused;
    }

    function getAsset(address asset_) internal view returns (IVault.AssetParams memory) {
        IVault.AssetStorage storage assetStorage = getAssetStorage();
        return assetStorage.assets[asset_];
    }

    function getBaseDecimals() internal view returns (uint8) {
        IVault.AssetStorage storage assetStorage = getAssetStorage();
        return assetStorage.assets[getBaseAsset()].decimals + decimalsOffset();
    }

    function getAllAssets() internal view returns (address[] memory assets_) {
        IVault.AssetStorage storage assetStorage = Storage.getAssetStorage();
        uint256 assetListLength = assetStorage.list.length;
        assets_ = new address[](assetListLength);
        for (uint256 i = 0; i < assetListLength; i++) {
            assets_[i] = address(assetStorage.list[i]);
        }
    }

    function getMaxDeposit() internal pure returns (uint256) {
        return type(uint256).max;
    }

    function getMaxMint() internal pure returns (uint256) {
        return type(uint256).max;
    }

    function getRate(address asset_) internal view returns (uint256) {
        return IRateProvider(getRateProvider()).getRate(asset_);
    }

    function convertAssetsToBase(address asset_, uint256 assets_) internal view returns (uint256) {
        return (assets_ * getRate(asset_)) / 1e18;
    }

    function convertBaseToAssets(address asset_, uint256 assets_) internal view returns (uint256) {
        return (assets_ * 1e18) / getRate(asset_);
    }

    function convertToAssets(address asset, uint256 shares, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 convertedShares = convertBaseToAssets(asset, shares);
        return convertedShares.mulDiv(getTotalSupply() + 10 ** decimalsOffset(), getTotalAssets() + 1, rounding);
    }

    function convertToShares(address asset_, uint256 assets_, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 convertedAssets = convertAssetsToBase(asset_, assets_);
        return convertedAssets.mulDiv(getTotalSupply() + 10 ** decimalsOffset(), getTotalAssets() + 1, rounding);
    }

    function decimalsOffset() internal pure returns (uint8) {
        return 0;
    }

    // ERC20

    function getTotalSupply() internal view returns (uint256) {
        ERC20Upgradeable.ERC20Storage storage erc20Storage = getERC20Storage();
        return erc20Storage._totalSupply;
    }

}
