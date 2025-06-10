// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Vault} from "src/Vault.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

library VaultVerification {
    error WithdrawerNotFound(address vault);

    function verifyProvider(Provider provider, address wusdc) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify rates for all LSDs
        vm.assertEq(provider.getRate(wusdc), 1e18, "wusdc rate should be 1e18");
        vm.assertEq(provider.getRate(MC.USDC), 1e18, "USDC rate should be 1e18");
    }

    function verifyViewer(MaxVaultViewer viewer, IVault vault) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.assertEq(address(viewer.getVault()), address(vault), "Viewer vault is correct");

        IVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        address[] memory assertsList = vault.getAssets();
        vm.assertEq(assets.length, assertsList.length, "Viewer assets length should match vault assets length");

        for (uint256 i = 0; i < assets.length; i++) {
            vm.assertEq(assets[i].asset, assertsList[i]);
            vm.assertEq(assets[i].canDeposit, vault.getAsset(assertsList[i]).active);
        }

        // Verify strategies are correct
        IVaultViewer.AssetInfo[] memory strategies = viewer.getStrategies();
        vm.assertEq(strategies.length, 1, "Viewer should have exactly 1 strategies");
    }
}
