// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {IContracts} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

library VaultVerification {
    error WithdrawerNotFound(address vault);

    function verifyProvider(Vault vault, Provider provider, IContracts contracts) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify rates for all underlying assets
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            vm.assertGt(
                provider.getRate(assets[i]),
                0,
                string.concat(IVault(assets[i]).symbol(), " rate should be greater than 0")
            );
        }

        // Base asset should always be 1:1
        vm.assertEq(provider.getRate(contracts.WBNB()), 1e18, "WETH rate should be 1:1");
    }

    function getWithdrawer(IVault vault) internal view returns (Withdrawer) {
        // Look up withdrawer by symbol
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            if (keccak256(bytes(IVault(assets[i]).symbol())) == keccak256(bytes(WithdrawerConfig.WITHDRAWER_SYMBOL))) {
                return Withdrawer(payable(assets[i]));
            }
        }

        revert WithdrawerNotFound(address(vault));
    }

    function verifyViewer(IVaultViewer viewer, IVault vault, IContracts contracts) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.assertEq(address(viewer.getVault()), address(vault), "Viewer vault is correct");

        IVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        address[] memory assertsList = vault.getAssets();
        vm.assertEq(assets.length, assertsList.length);

        for (uint256 i = 0; i < assets.length; i++) {
            vm.assertEq(assets[i].asset, assertsList[i]);
            vm.assertEq(assets[i].canDeposit, vault.getAsset(assertsList[i]).active);
        }

        vm.assertTrue(
            MaxVaultViewer(address(viewer)).isUnderlyingAsset(contracts.WBNB()), "WBNB should be an underlying asset"
        );
    }
}
