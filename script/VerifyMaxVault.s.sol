// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {console} from "lib/forge-std/src/console.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {BaseScript} from "script/BaseScript.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {Provider} from "src/module/Provider.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {ParaswapRules} from "script/rules/ParaswapRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {SuperUsdcRules} from "script/rules/SuperUsdcRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyMaxVault
contract VerifyMaxVault is BaseScript, Test {
    bool public isTestEnv = false;

    function setIsTestEnv(bool _isTestEnv) public {
        isTestEnv = _isTestEnv;
    }

    function symbol() public view virtual override returns (string memory) {
        return "ynUSDx";
    }

    function run() public {
        _setup();
        _loadDeployment();
        if (!isTestEnv) {
            assertNotEq(msg.sender, deployer, "msg.sender should not be deploye as this is a verifier script.");
        }
        verify();
    }

    function verify() public view {
        assertNotEq(address(vaultProxy), address(0), "vault is not set");

        console.log("==============================================");
        console.log("=          VERIFYING VAULT SETUP             =");
        console.log("==============================================");
        console.log("Verifying vault at:       ", address(vaultProxy));
        console.log("==============================================");

        assertEq(vaultProxy.name(), "YieldNest USD Max Vault", "name is invalid");
        assertEq(vaultProxy.symbol(), "ynUSDx", "symbol is invalid");
        assertEq(vaultProxy.decimals(), 18, "decimals is invalid");
        assertEq(vaultProxy.provider(), address(rateProvider), "provider is invalid");
        assertEq(vaultProxy.baseWithdrawalFee(), 100000, "base withdrawal fee is invalid");
        assertEq(vaultProxy.countNativeAsset(), false, "count native asset is invalid");
        assertFalse(vaultProxy.alwaysComputeTotalAssets(), "always compute total assets is invalid");
        IVault.AssetParams memory asset;
        address[] memory assets = vaultProxy.getAssets();

        assertEq(assets[0], MC.WRAPPED_USDC, "assets[0] is invalid");
        asset = vaultProxy.getAsset(MC.WRAPPED_USDC);
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, false, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], MC.USDC, "assets[1] is invalid");
        asset = vaultProxy.getAsset(MC.USDC);
        assertEq(asset.active, true, "asset[1].active is invalid");
        assertEq(asset.index, 1, "asset[1].index is invalid");

        assertEq(vaultProxy.asset(), MC.USDC, "asset is invalid");

        {
            // Verify proxy admin and implementation addresses
            console.log("==============================================");
            console.log("=        VERIFYING PROXY CONFIGURATION      =");
            console.log("==============================================");

            // Verify vault proxy configuration
            address vaultImpl = ProxyUtils.getImplementation(address(vaultProxy));
            address vaultAdmin = ProxyUtils.getProxyAdmin(address(vaultProxy));
            assertEq(vaultImpl, address(vaultImplementation), "Vault implementation address mismatch");
            assertEq(vaultAdmin, vaultProxyAdmin, "Vault proxy admin address mismatch");
            console.log("\u2705 Vault implementation:     ", vaultImpl);
            console.log("\u2705 Vault proxy admin:        ", vaultAdmin);
        }

        console.log("Verifying deposit and approval rules.");
        RulesVerification.verifyProcessorRule(
            vaultProxy, BaseRules.getDepositRule(MC.MORPHO_GAUNTLET_USDC_VAULT, address(vaultProxy))
        );
        RulesVerification.verifyProcessorRule(
            vaultProxy, BaseRules.getDepositRule(MC.SUPER_USDC_VAULT, address(vaultProxy))
        );
        address[] memory usdcApprovalAllowList = new address[](3);
        usdcApprovalAllowList[0] = MC.MORPHO_GAUNTLET_USDC_VAULT;
        usdcApprovalAllowList[1] = MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER;
        usdcApprovalAllowList[2] = MC.SUPER_USDC_VAULT;
        RulesVerification.verifyProcessorRule(vaultProxy, BaseRules.getApprovalRule(MC.USDC, usdcApprovalAllowList));

        console.log("Verifying paraswap rules.");
        SafeRules.RuleParams[] memory rules =
            ParaswapRules.getParaswapRules(MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, address(paraswapValidator));
        for (uint256 i; i < rules.length; i++) {
            RulesVerification.verifyProcessorRule(vaultProxy, rules[i]);
        }

        console.log("Verifying super usdc rules.");
        SafeRules.RuleParams[] memory superUsdcRules =
            SuperUsdcRules.getSuperUsdcRedeemRules(MC.SUPER_USDC_VAULT, address(vaultProxy));
        for (uint256 i; i < superUsdcRules.length; i++) {
            RulesVerification.verifyProcessorRule(vaultProxy, superUsdcRules[i]);
        }

        RolesVerification.verifyDefaultRoles(vaultProxy, timelock, actors);
        RolesVerification.verifyRole(
            vaultProxy, actors.FEE_MANAGER(), vaultProxy.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        RolesVerification.verifyProxyRoles(address(vaultProxy), vaultProxyAdmin, address(timelock));

        assertFalse(vaultProxy.paused(), "Vault should not be paused");

        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);

        RolesVerification.verifyTemporaryRoles(vaultProxy, deployer);

        VaultVerification.verifyProvider(vaultProxy, Provider(address(rateProvider)));

        assertEq(vaultProxy.VAULT_VERSION(), "0.3.0", "Vault version should be 0.3.0");
        console.log("\u2705 Vault version:          ", vaultProxy.VAULT_VERSION());
        console.log("==============================================");

        VaultVerification.verifyViewer(viewerProxy, vaultProxy);

        RolesVerification.verifyViewerRoles(MaxVaultViewer(address(viewerProxy)), actors, deployer);

        RolesVerification.verifyProxyRoles(address(viewerProxy), viewerProxyAdmin, actors.ADMIN());

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

        uint256 totalAssets = vaultProxy.totalAssets();
        console.log("Total assets:", totalAssets);

        // Print rate by converting 1e18 shares to assets
        uint256 oneShare = 1e18;
        uint256 assetAmount = vaultProxy.convertToAssets(oneShare);
        console.log("Vault rate (1 share in assets):", assetAmount);
    }
}
