// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {IERC20Metadata, Math} from "src/Common.sol";

contract VaultMainnetViewerTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    MaxVaultViewer public viewer;

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));

        SetupVault setupVault = new SetupVault();
        setupVault.upgrade();

        viewer = setupVault.deployViewer(vault);
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
        assertEq(assetsInfo.length, 10);

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
        assertEq(assetsInfo.length, 10);

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

    function test_Vault_Viewer_isUnderlyingAsset() public {
        assertFalse(viewer.isUnderlyingAsset(MC.WETH));
        assertFalse(viewer.isUnderlyingAsset(vault.buffer()));
        assertFalse(viewer.isUnderlyingAsset(MC.STETH));
        assertFalse(viewer.isUnderlyingAsset(MC.YNETH));
        assertFalse(viewer.isUnderlyingAsset(MC.YNLSDE));

        address[] memory underlyingAssets = new address[](3);
        underlyingAssets[0] = MC.WETH;
        underlyingAssets[1] = MC.STETH;
        underlyingAssets[2] = vault.buffer();

        vm.prank(ADMIN);
        viewer.addUnderlyingAssets(underlyingAssets);

        assertTrue(viewer.isUnderlyingAsset(MC.WETH));
        assertTrue(viewer.isUnderlyingAsset(MC.STETH));
        assertTrue(viewer.isUnderlyingAsset(vault.buffer()));

        assertEq(viewer.getUnderlyingAssetsLength(), 3);

        address[] memory underlyingAssets2 = new address[](1);
        underlyingAssets2[0] = vault.buffer();

        vm.prank(ADMIN);
        viewer.removeUnderlyingAssets(underlyingAssets2);

        assertTrue(viewer.isUnderlyingAsset(MC.WETH));
        assertTrue(viewer.isUnderlyingAsset(MC.STETH));
        assertFalse(viewer.isUnderlyingAsset(vault.buffer()));

        assertEq(viewer.getUnderlyingAssetsLength(), 2);
    }

    function test_Vault_Viewer_getStrategies() public {
        IVaultViewer.AssetInfo[] memory assetsInfo = viewer.getUnderlyingAssets();
        {
            IVaultViewer.AssetInfo[] memory strategies = viewer.getStrategies();

            assertEq(assetsInfo.length, strategies.length);
            assertEq(strategies.length, 10);
        }

        address[] memory underlyingAssets = new address[](2);
        underlyingAssets[0] = MC.WETH;
        underlyingAssets[1] = MC.STETH;

        vm.prank(ADMIN);
        viewer.addUnderlyingAssets(underlyingAssets);

        {
            IVaultViewer.AssetInfo[] memory strategies = viewer.getStrategies();

            assertEq(strategies.length, 8);

            assertEq(strategies[0].asset, MC.YNETH);
            assertEq(strategies[1].asset, MC.YNLSDE);
            assertEq(strategies[2].asset, MC.EULER_WETH_22_VAULT);
        }
    }
}
