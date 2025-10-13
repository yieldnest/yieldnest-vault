// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Vault} from "src/Vault.sol";
import {IContracts} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";

library VaultVerification {
    error WithdrawerNotFound(address vault);

    function verifyProvider(Vault vault, Provider provider) internal view {
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
        vm.assertEq(provider.getRate(MC.USDC), 1e18, "USDC rate should be 1:1");
    }

    function verifyViewer(IVaultViewer viewer, IVault vault) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.assertEq(address(viewer.getVault()), address(vault), "Viewer vault is correct");

        IVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        address[] memory assertsList = vault.getAssets();
        vm.assertEq(assets.length, assertsList.length);

        for (uint256 i = 0; i < assets.length; i++) {
            vm.assertEq(assets[i].asset, assertsList[i]);
            vm.assertEq(assets[i].canDeposit, vault.getAsset(assertsList[i]).active);
        }

        vm.assertTrue(MaxVaultViewer(address(viewer)).isUnderlyingAsset(MC.USDC), "USDC should be an underlying asset");
    }

    function getWithdrawer(IVault vault) internal view returns (Withdrawer) {
        Withdrawer withdrawer = _getWithdrawer(vault);
        if (address(withdrawer) != address(0)) {
            return withdrawer;
        }

        revert WithdrawerNotFound(address(vault));
    }

    function safeGetWithdrawer(IVault vault) internal view returns (Withdrawer) {
        return _getWithdrawer(vault);
    }

    function _getWithdrawer(IVault vault) internal view returns (Withdrawer) {
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            if (keccak256(bytes(IVault(assets[i]).symbol())) == keccak256(bytes(WithdrawerConfig.WITHDRAWER_SYMBOL))) {
                return Withdrawer(payable(assets[i]));
            }
        }

        return Withdrawer(payable(address(0)));
    }
}
