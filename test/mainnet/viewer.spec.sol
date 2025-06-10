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
    function setUp() public override {
        super.setUp();
    }

    // function test_Vault_Viewer_getVault() public view {
    //     assertEq(viewer.getVault(), address(vault));
    // }

    // function test_Vault_Viewer_getRate() public view {
    //     uint256 totalSupply = vault.totalSupply();
    //     uint256 totalAssets = vault.totalAssets();
    //     uint256 expected = 1 ether;
    //     if (totalSupply > 0 && totalAssets > 0) {
    //         expected = 1 ether * totalAssets * 1e12 / totalSupply;
    //     }

    //     assertEq(viewer.getRate(), expected);
    // }

    // function test_Vault_Viewer_getAssets() public view {
    //     IVaultViewer.AssetInfo[] memory assetsInfo = viewer.getAssets();

    //     address[] memory assets = vault.getAssets();
    //     uint256 totalAssets = vault.totalAssets();

    //     assertEq(assetsInfo.length, assets.length);
    //     assertEq(assetsInfo.length, 2);

    //     for (uint256 i = 0; i < assets.length; i++) {
    //         IERC20Metadata asset = IERC20Metadata(assets[i]);
    //         IVaultViewer.AssetInfo memory assetInfo = assetsInfo[i];

    //         assertEq(assetInfo.asset, assets[i]);
    //         assertEq(assetInfo.name, asset.name());
    //         assertEq(assetInfo.symbol, asset.symbol());
    //         assertEq(assetInfo.decimals, asset.decimals());

    //         IProvider provider = IProvider(vault.provider());
    //         uint256 rate = provider.getRate(assets[i]);
    //         assertEq(assetInfo.rate, rate);

    //         uint256 assetBalance = asset.balanceOf(address(vault));
    //         uint256 baseBalance = Math.mulDiv(assetBalance, rate, 10 ** assetInfo.decimals, Math.Rounding.Floor);
    //         assertEq(assetInfo.totalBalanceInUnitOfAccount, baseBalance);
    //         assertEq(assetInfo.totalBalanceInAsset, assetBalance);
    //         assertEq(assetInfo.canDeposit, vault.getAsset(assets[i]).active);
    //         assertEq(assetInfo.ratioOfTotalAssets, baseBalance * 1000_000 / totalAssets);
    //     }
    // }

    // function test_Vault_Viewer_getUnderlyingAssets() public view {
    //     IVaultViewer.AssetInfo[] memory assetsInfo = viewer.getUnderlyingAssets();

    //     address[] memory assets = vault.getAssets();
    //     uint256 totalAssets = vault.totalAssets();

    //     assertEq(assetsInfo.length, assets.length);
    //     assertEq(assetsInfo.length, 11);

    //     for (uint256 i = 0; i < assets.length; i++) {
    //         IERC20Metadata asset = IERC20Metadata(assets[i]);
    //         IVaultViewer.AssetInfo memory assetInfo = assetsInfo[i];

    //         assertEq(assetInfo.asset, assets[i]);
    //         assertEq(assetInfo.name, asset.name());
    //         assertEq(assetInfo.symbol, asset.symbol());
    //         assertEq(assetInfo.decimals, asset.decimals());

    //         IProvider provider = IProvider(vault.provider());
    //         uint256 rate = provider.getRate(assets[i]);
    //         assertEq(assetInfo.rate, rate);

    //         uint256 assetBalance = asset.balanceOf(address(vault));
    //         uint256 baseBalance = Math.mulDiv(assetBalance, rate, 10 ** assetInfo.decimals, Math.Rounding.Floor);
    //         assertEq(assetInfo.totalBalanceInUnitOfAccount, baseBalance);
    //         assertEq(assetInfo.totalBalanceInAsset, assetBalance);
    //         assertEq(assetInfo.canDeposit, vault.getAsset(assets[i]).active);
    //         assertEq(assetInfo.ratioOfTotalAssets, baseBalance * 1000_000 / totalAssets);
    //     }
    // }

    // function test_Vault_Viewer_isUnderlyingAsset() public {
    //     assertTrue(viewer.isUnderlyingAsset(MC.WETH));
    //     assertFalse(viewer.isUnderlyingAsset(vault.buffer()));
    //     assertTrue(viewer.isUnderlyingAsset(MC.STETH));
    //     assertTrue(viewer.isUnderlyingAsset(MC.YNETH));
    //     assertTrue(viewer.isUnderlyingAsset(MC.YNLSDE));

    //     // Get the length before adding a new asset
    //     uint256 lengthBefore = viewer.getUnderlyingAssetsLength();

    //     address[] memory underlyingAssets = new address[](1);
    //     underlyingAssets[0] = vault.buffer();

    //     vm.prank(YnDev);
    //     viewer.addUnderlyingAssets(underlyingAssets);

    //     assertTrue(viewer.isUnderlyingAsset(vault.buffer()));

    //     // Assert length increased by exactly 1
    //     assertEq(viewer.getUnderlyingAssetsLength(), lengthBefore + 1);

    //     address[] memory underlyingAssets2 = new address[](1);
    //     underlyingAssets2[0] = vault.buffer();

    //     vm.prank(YnDev);
    //     viewer.removeUnderlyingAssets(underlyingAssets2);

    //     assertFalse(viewer.isUnderlyingAsset(vault.buffer()));

    //     assertEq(viewer.getUnderlyingAssetsLength(), lengthBefore);
    // }

    // function test_Vault_Viewer_getStrategies() public {
    //     uint256 strategiesLengthBefore;
    //     {
    //         IVaultViewer.AssetInfo[] memory strategies = viewer.getStrategies();
    //         strategiesLengthBefore = strategies.length;
    //         assertEq(strategies.length, 4, "There should be exactly 4 strategies");
    //     }

    //     address[] memory underlyingAssets = new address[](1);
    //     underlyingAssets[0] = vault.buffer();

    //     vm.prank(YnDev);
    //     viewer.addUnderlyingAssets(underlyingAssets);

    //     {
    //         IVaultViewer.AssetInfo[] memory strategies = viewer.getStrategies();

    //         assertEq(
    //             strategies.length,
    //             strategiesLengthBefore - 1,
    //             "Strategies length should decrease by 1 after adding buffer as underlying asset"
    //         );
    //     }
    // }
}
