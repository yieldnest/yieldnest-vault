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
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";

library VaultVerification {
    error WithdrawerNotFound(address vault);

    function verifyProvider(Provider provider, address wusdc) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify rates for all LSDs
        vm.assertEq(provider.getRate(wusdc), 1e18, "wusdc rate should be 1e18");
        vm.assertEq(provider.getRate(MC.USDC), 1e18, "USDC rate should be 1e18");
    }

    function verifyWusdc(address wusdc) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        vm.assertEq(IERC20Metadata(wusdc).decimals(), 18, "wusdc decimals should be 18");
        vm.assertEq(IERC20Metadata(wusdc).name(), "Wrapped USDC", "wusdc name should be Wrapped USDC");
        vm.assertEq(IERC20Metadata(wusdc).symbol(), "WUSDC", "wusdc symbol should be wusdc");
        vm.assertEq(IERC4626(wusdc).asset(), MC.USDC, "wusdc total supply should be 0");
        vm.assertEq(IERC4626(wusdc).convertToAssets(1e18), 1e6, "wusdc convertToAssets should be 1e18");
        vm.assertEq(IERC4626(wusdc).convertToShares(1e6), 1e18, "wusdc convertToAssets should be 1e18");
        vm.assertEq(WrappedToken(wusdc).decimalsOffset(), 12, "wusdc convertToShares should be 1e18");
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
