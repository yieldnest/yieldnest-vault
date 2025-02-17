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
        _loadDeployment();
        _setup();

        verify();
    }

    function verify() public view {
        assertNotEq(address(vault), address(0), "vault is not set");

        assertEq(vault.name(), "ynETH MAX", "name is invalid");
        assertEq(vault.symbol(), "ynETHx", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");
        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.baseWithdrawalFee(), 100000, "base withdrawal fee is invalid");
        assertEq(vault.countNativeAsset(), true, "count native asset is invalid");
        assertFalse(vault.alwaysComputeTotalAssets(), "always compute total assets is invalid");
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

        // TODO: Add rest of assertions and verifications
        // Verify provider configuration
        VaultVerification.verifyProvider(Provider(address(rateProvider)), withdrawer);

        // Verify vault configuration using VaultVerification library
        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        // Verify processor rules
        VaultVerification.verifyRules(vault);

        // verify actors  & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // Verify withdrawer configuration
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // Verify withdrawer rules
        VaultVerification.verifyWithdrawerRules(withdrawer);

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
        // FIXME: TODO: reenable this once viewer is deployed
        //RolesVerification.verifyProxyRoles(address(viewer), viewerProxyAdmin, actors.ADMIN());

        // verify timelock roles
        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);

        // verify temporary roles
        RolesVerification.verifyTemporaryRoles(vault, deployer);
        RolesVerification.verifyTemporaryRoles(withdrawer, deployer);

        // FIXME: TODO: reenable this once viewer is deployed
        // verify viewer
        // VaultVerification.verifyViewer(viewer, vault);
        // assertTrue(
        //     MaxVaultViewer(address(viewer)).isUnderlyingAsset(contracts.WETH()), "WETH should be an underlying asset"
        // );

        assertFalse(withdrawer.paused(), "Withdrawer should not be paused");
        assertFalse(vault.paused(), "Vault should not be paused");
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
