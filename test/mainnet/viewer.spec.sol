// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {IERC20Metadata, Math} from "src/Common.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";

contract VaultMainnetViewerTest is BaseIntegrationTest {
    MaxVaultViewer public viewer;

    function setUp() public override {
        super.setUp();

        viewer = MaxVaultViewer(MC.YNETHX_VIEWER);
    }

    function test_Vault_Viewer_getVault() public view {
        assertEq(viewer.getVault(), address(vault));
    }

    function test_Vault_Viewer_getRate() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 expected = 1 ether;
        if (totalSupply > 0 && totalAssets > 0) {
            expected = 1 ether * totalAssets / totalSupply;
        }

        assertEq(viewer.getRate(), expected);
    }

    function test_Vault_Viewer_getAssets() public view {
        IVaultViewer.AssetInfo[] memory assetsInfo = viewer.getAssets();

        address[] memory assets = vault.getAssets();
        uint256 totalAssets = vault.totalAssets();

        assertEq(assetsInfo.length, assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20Metadata asset = IERC20Metadata(assets[i]);
            IVaultViewer.AssetInfo memory assetInfo = assetsInfo[i];

            assertEq(assetInfo.asset, assets[i]);
            assertEq(assetInfo.name, asset.name());
            assertEq(assetInfo.symbol, asset.symbol());
            assertEq(assetInfo.decimals, asset.decimals());

            IProvider provider = IProvider(vault.provider());
            uint256 rate = provider.getRate(assets[i]);
            assertEq(assetInfo.rate, rate);

            uint256 assetBalance = asset.balanceOf(address(vault));
            uint256 baseBalance = Math.mulDiv(assetBalance, rate, 10 ** assetInfo.decimals, Math.Rounding.Floor);
            assertEq(assetInfo.totalBalanceInUnitOfAccount, baseBalance);
            assertEq(assetInfo.totalBalanceInAsset, assetBalance);
            assertEq(assetInfo.canDeposit, vault.getAsset(assets[i]).active);
            assertEq(assetInfo.ratioOfTotalAssets, baseBalance * 1000_000 / totalAssets);
        }
    }

    function test_Vault_Viewer_getUnderlyingAssets() public view {
        IVaultViewer.AssetInfo[] memory assetsInfo = viewer.getUnderlyingAssets();

        address[] memory assets = vault.getAssets();
        uint256 totalAssets = vault.totalAssets();

        assertEq(assetsInfo.length, assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20Metadata asset = IERC20Metadata(assets[i]);
            IVaultViewer.AssetInfo memory assetInfo = assetsInfo[i];

            assertEq(assetInfo.asset, assets[i]);
            assertEq(assetInfo.name, asset.name());
            assertEq(assetInfo.symbol, asset.symbol());
            assertEq(assetInfo.decimals, asset.decimals());

            IProvider provider = IProvider(vault.provider());
            uint256 rate = provider.getRate(assets[i]);
            assertEq(assetInfo.rate, rate);

            uint256 assetBalance = asset.balanceOf(address(vault));
            uint256 baseBalance = Math.mulDiv(assetBalance, rate, 10 ** assetInfo.decimals, Math.Rounding.Floor);
            assertEq(assetInfo.totalBalanceInUnitOfAccount, baseBalance);
            assertEq(assetInfo.totalBalanceInAsset, assetBalance);
            assertEq(assetInfo.canDeposit, vault.getAsset(assets[i]).active);
            assertEq(assetInfo.ratioOfTotalAssets, baseBalance * 1000_000 / totalAssets);
        }
    }
}
