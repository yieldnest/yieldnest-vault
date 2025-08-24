// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {console} from "lib/forge-std/src/console.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {Provider} from "src/module/Provider.sol";
import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

import {Test} from "lib/forge-std/src/Test.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyMaxVault
contract VerifyMaxVault is BaseScript, Test {
    function symbol() public view virtual override returns (string memory) {
        return "ynETHx";
    }

    function run() public {
        _setup();
        _loadDeployment();
        assertNotEq(msg.sender, deployer, "msg.sender should not be deploye as this is a verifier script.");
        verify();
    }

    function verify() public view {
        assertNotEq(address(vault), address(0), "vault is not set");

        console.log("==============================================");
        console.log("=          VERIFYING VAULT SETUP            =");
        console.log("==============================================");
        console.log("Verifying vault at:       ", address(vault));
        console.log("==============================================");

        assertEq(vault.name(), "ynETH MAX", "name is invalid");
        assertEq(vault.symbol(), "ynETHx", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");
        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.baseWithdrawalFee(), 250000, "base withdrawal fee is invalid");
        assertEq(vault.countNativeAsset(), true, "count native asset is invalid");
        assertFalse(vault.alwaysComputeTotalAssets(), "always compute total assets is invalid");

        {
            // Verify proxy admin and implementation addresses
            console.log("==============================================");
            console.log("=        VERIFYING PROXY CONFIGURATION      =");
            console.log("==============================================");

            // Verify vault proxy configuration
            address vaultImpl = ProxyUtils.getImplementation(address(vault));
            address vaultAdmin = ProxyUtils.getProxyAdmin(address(vault));
            assertEq(vaultImpl, address(implementation), "Vault implementation address mismatch");
            assertEq(vaultAdmin, vaultProxyAdmin, "Vault proxy admin address mismatch");
            console.log("\u2705 Vault implementation:     ", vaultImpl);
            console.log("\u2705 Vault proxy admin:        ", vaultAdmin);

            // Verify withdrawer proxy configuration
            address withdrawerImpl = ProxyUtils.getImplementation(address(withdrawer));
            address withdrawerAdmin = ProxyUtils.getProxyAdmin(address(withdrawer));

            assertEq(withdrawerImpl, address(withdrawerImplementation), "Withdrawer implementation address mismatch");
            assertEq(withdrawerAdmin, withdrawerProxyAdmin, "Withdrawer proxy admin address mismatch");
            console.log("\u2705 Withdrawer implementation:", withdrawerImpl);
            console.log("\u2705 Withdrawer proxy admin:   ", withdrawerAdmin);
            console.log("==============================================");
        }

        IVault.AssetParams memory asset;
        address[] memory assets = vault.getAssets();

        assertEq(assets[0], contracts.WETH(), "assets[0] is invalid");

        asset = vault.getAsset(contracts.WETH());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        console.log("Verifying WETH deposit and withdraw rules.");

        // Get withdrawer from vault assets
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        console.log("==============================================");
        console.log("=        VERIFYING WITHDRAWER SETUP         =");
        console.log("==============================================");
        console.log("Verifying withdrawer at:   ", address(withdrawer));
        console.log("==============================================");

        assertEq(vault.VAULT_VERSION(), "0.3.0", "Vault version should be 0.3.0");
        console.log("\u2705 Vault version:          ", vault.VAULT_VERSION());
        console.log("==============================================");

        assertEq(withdrawer.STRATEGY_VERSION(), "0.2.0", "Strategy version should be 0.2.0");
        console.log("\u2705 Strategy version:       ", withdrawer.STRATEGY_VERSION());

        // Verify provider configuration
        VaultVerification.verifyProvider(Provider(address(rateProvider)), withdrawer);

        // Verify vault configuration using VaultVerification library
        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        // verify actors  & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // Verify withdrawer configuration
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // verify actors & timelock roles on withdrawer
        RolesVerification.verifyDefaultRoles(withdrawer, timelock, actors);
        RolesVerification.verifyRole(
            withdrawer, address(vault), withdrawer.ALLOCATOR_ROLE(), true, "YnETHx has ALLOCATOR_ROLE"
        );

        address withdrawerProxyAdmin = ProxyUtils.getProxyAdmin(address(withdrawer));

        // verify proxy roles on withdrawer
        RolesVerification.verifyProxyRoles(address(withdrawer), withdrawerProxyAdmin, address(timelock));

        // verify proxy roles
        RolesVerification.verifyProxyRoles(address(vault), vaultProxyAdmin, address(timelock));
        // verify viewer roles
        RolesVerification.verifyProxyRoles(address(viewer), viewerProxyAdmin, actors.UPDATER());

        // verify timelock roles
        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);

        // verify temporary roles
        RolesVerification.verifyTemporaryRoles(vault, deployer);
        RolesVerification.verifyTemporaryRoles(withdrawer, deployer);

        VaultVerification.verifyViewer(MaxVaultViewer(address(viewer)), vault);
        assertTrue(
            MaxVaultViewer(address(viewer)).isUnderlyingAsset(contracts.WETH()), "WETH should be an underlying asset"
        );

        // Verify configurer does not have DEFAULT_ADMIN_ROLE
        assertFalse(
            vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), 0x3794d53a890ee7e6B1515d7E053B2E51934ffB7B),
            "Configurer should not have DEFAULT_ADMIN_ROLE"
        );
        console.log(
            "\u2705 Configurer ROLE CHECK - should not have DEFAULT_ADMIN_ROLE: OK for 0x3794d53a890ee7e6B1515d7E053B2E51934ffB7B"
        );

        assertFalse(withdrawer.paused(), "Withdrawer should not be paused");
        assertFalse(vault.paused(), "Vault should not be paused");

        console.log("==============================================");
        console.log("MANUAL VERIFICATION REQUIRED");
        console.log("==============================================");
        console.log("Verify total assets and vault rate are reasonable:");
        console.log("- Total assets should be the same as the previous total assets");
        console.log("- Vault rate should be the same as the previous vault rate (vault.convertToAssets(1e18)");
        console.log("==============================================");

        console.log("==============================================");
        console.log("TOTAL ASSETS AND VAULT RATE:");
        console.log("==============================================");

        uint256 totalAssets = vault.totalAssets();
        console.log("Total assets:", totalAssets);

        // Print rate by converting 1e18 shares to assets
        uint256 oneShare = 1e18;
        uint256 assetAmount = vault.convertToAssets(oneShare);
        console.log("Vault rate (1 share in assets):", assetAmount);
    }

    function _checkForAsset(address asset) internal view returns (bool isIncluded, uint256 index) {
        address[] memory assets = vault.getAssets();

        for (uint256 i; i < assets.length;) {
            if (assets[i] == asset) {
                isIncluded = true;
                index = i;
                break;
            }
            {
                i++;
            }
        }
    }
}
