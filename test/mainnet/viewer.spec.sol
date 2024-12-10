// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseVaultViewer} from "src/BaseVaultViewer.sol";
import {IERC20Metadata, Math} from "src/Common.sol";

contract VaultMainnetViewerTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    BaseVaultViewer public baseVaultViewer;

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));

        SetupVault setupVault = new SetupVault();
        setupVault.upgrade();

        baseVaultViewer = setupVault.deployViewer(vault);
    }

    function test_Vault_Viewer_getVault() public view {
        assertEq(baseVaultViewer.getVault(), address(vault));
    }

    function test_Vault_Viewer_getRate() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 expected = 1 ether;
        if (totalSupply > 0 && totalAssets > 0) {
            expected = 1 ether * totalAssets / totalSupply;
        }

        assertEq(baseVaultViewer.getRate(), expected);
    }

    function test_Vault_Viewer_getAssets() public view {
        BaseVaultViewer.AssetInfo[] memory assetsInfo = baseVaultViewer.getAssets();

        address[] memory assets = vault.getAssets();
        uint256 totalAssets = vault.totalAssets();

        assertEq(assetsInfo.length, assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20Metadata asset = IERC20Metadata(assets[i]);
            BaseVaultViewer.AssetInfo memory assetInfo = assetsInfo[i];

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
