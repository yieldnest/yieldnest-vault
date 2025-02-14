// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {YieldNestRules} from "script/rules/YieldNestRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {OriginRules} from "script/rules/OriginRules.sol";
import {StakedEtherRules} from "script/rules/StakedEtherRules.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";

library VaultVerification {
    error WithdrawerNotFound(address vault);

    function verifyVaultConfiguration(Vault vault, Withdrawer withdrawer) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify core vault configuration
        vm.assertEq(vault.alwaysComputeTotalAssets(), false);
        vm.assertEq(vault.countNativeAsset(), true);
        vm.assertEq(vault.decimals(), 18);
        vm.assertEq(vault.baseWithdrawalFee(), 1e5); // 0.1%
        vm.assertFalse(vault.paused(), "Vault should not be paused");

        // Verify deposit assets
        address[] memory activeAssets = new address[](3);
        activeAssets[0] = MC.WETH;
        activeAssets[1] = MC.YNETH;
        activeAssets[2] = MC.YNLSDE;

        for (uint256 i = 0; i < activeAssets.length; i++) {
            IVault.AssetParams memory asset = vault.getAsset(activeAssets[i]);
            vm.assertTrue(asset.active);
            vm.assertEq(asset.decimals, 18);
        }

        address[] memory inactiveAssets = new address[](8);
        inactiveAssets[0] = MC.EULER_WETH_22_VAULT;
        inactiveAssets[1] = MC.CURVE_LP_YNETH_YNLSDE_STRATEGY;
        inactiveAssets[2] = address(withdrawer);
        inactiveAssets[3] = MC.WSTETH;
        inactiveAssets[4] = MC.WOETH;
        inactiveAssets[5] = MC.STETH;
        inactiveAssets[6] = MC.OETH;
        inactiveAssets[7] = MC.SMOKEHOUSE_WSTETH;

        for (uint256 i = 0; i < inactiveAssets.length; i++) {
            IVault.AssetParams memory asset = vault.getAsset(inactiveAssets[i]);
            vm.assertFalse(asset.active);
            vm.assertEq(asset.decimals, 18);
        }

        // Verify total number of assets
        address[] memory assets = vault.getAssets();
        // WETH, YNETH, YNLSDE, EULER_WETH_22_VAULT, CURVE_LP_YNETH_YNLSDE_STRATEGY, withdrawer, WSTETH, WOETH, STETH, OETH, SMOKEHOUSE_WSTETH
        vm.assertEq(assets.length, 11);

        // Verify buffer configuration
        vm.assertEq(vault.buffer(), MC.EULER_WETH_22_VAULT, "Buffer should be set to Euler WETH 22 vault");
    }

    function verifyProvider(Provider provider, Withdrawer withdrawer) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify rates for all LSDs
        vm.assertGt(provider.getRate(MC.STETH), 0, "stETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.WSTETH), 0, "wstETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.RETH), 0, "rETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.SFRXETH), 0, "sfrxETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.OETH), 0, "OETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.WOETH), 0, "wOETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.SWELL), 0, "SWELL rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.METH), 0, "mETH rate should be greater than 0");

        // Verify rates for YieldNest tokens
        vm.assertGt(provider.getRate(MC.YNETH), 0, "ynETH rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.YNLSDE), 0, "ynLSDE rate should be greater than 0");

        // Verify rates for strategies
        vm.assertGt(
            provider.getRate(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY), 0, "Curve LP strategy rate should be greater than 0"
        );
        vm.assertGt(provider.getRate(address(withdrawer)), 0, "Withdrawer rate should be greater than 0");
        vm.assertGt(provider.getRate(MC.SMOKEHOUSE_WSTETH), 0, "Smokehouse WSTETH rate should be greater than 0");

        // Base asset should always be 1:1
        vm.assertEq(provider.getRate(MC.WETH), 1e18, "WETH rate should be 1:1");
    }

    function verifyWithdrawerConfiguration(Vault vault, Withdrawer withdrawer) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify withdrawer configuration
        vm.assertTrue(Withdrawer(withdrawer).hasRole(Withdrawer(withdrawer).ALLOCATOR_ROLE(), address(vault)));

        // Verify withdrawer deposit assets
        {
            IVault.AssetParams memory asset = Withdrawer(withdrawer).getAsset(MC.WETH);
            vm.assertTrue(asset.active);
            vm.assertEq(asset.decimals, 18);
            vm.assertTrue(Withdrawer(withdrawer).getAssetWithdrawable(MC.WETH));
        }
        address[] memory assets = new address[](9);
        assets[0] = MC.YNETH;
        assets[1] = MC.YNLSDE;
        assets[2] = MC.WOETH;
        assets[3] = MC.OETH;
        assets[4] = MC.WSTETH;
        assets[5] = MC.STETH;
        assets[6] = MC.METH;
        assets[7] = MC.SFRXETH;
        assets[8] = MC.WETH;

        for (uint256 i = 0; i < assets.length; i++) {
            IVault.AssetParams memory asset = Withdrawer(withdrawer).getAsset(assets[i]);
            vm.assertTrue(asset.active);
            vm.assertEq(asset.decimals, 18);
            if (assets[i] == MC.WETH) {
                vm.assertTrue(Withdrawer(withdrawer).getAssetWithdrawable(assets[i]));
            } else {
                vm.assertFalse(Withdrawer(withdrawer).getAssetWithdrawable(assets[i]));
            }
        }
    }

    function verifyWithdrawerRules(Withdrawer withdrawer) internal view {
        {
            // ynETH withdrawal queue
            RulesVerification.verifyProcessorRule(
                withdrawer, BaseRules.getApprovalRule(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER)
            );
            RulesVerification.verifyProcessorRule(
                withdrawer, WithdrawerRules.getRequestWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER)
            );

            RulesVerification.verifyProcessorRule(
                withdrawer,
                WithdrawerRules.getClaimWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, address(withdrawer))
            );
        }

        {
            // ynLSDe withdrawal queue
            RulesVerification.verifyProcessorRule(
                withdrawer, BaseRules.getApprovalRule(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER)
            );
            RulesVerification.verifyProcessorRule(
                withdrawer, WithdrawerRules.getRequestWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER)
            );

            RulesVerification.verifyProcessorRule(
                withdrawer,
                WithdrawerRules.getClaimWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, address(withdrawer))
            );
        }

        {
            // wstETH withdrawal queue
            RulesVerification.verifyProcessorRule(
                withdrawer, BaseRules.getApprovalRule(MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE)
            );
            RulesVerification.verifyProcessorRule(
                withdrawer,
                WithdrawerRules.getRequestWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(withdrawer))
            );
            RulesVerification.verifyProcessorRule(
                withdrawer,
                WithdrawerRules.getClaimWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(withdrawer))
            );
        }

        {
            // wrap/unwrap wstETH
            RulesVerification.verifyProcessorRule(withdrawer, StakedEtherRules.getWrapRule(MC.WSTETH));
            RulesVerification.verifyProcessorRule(withdrawer, StakedEtherRules.getUnwrapRule(MC.WSTETH));
        }

        {
            // wrap/unwrap woeth
            RulesVerification.verifyProcessorRule(withdrawer, BaseRules.getApprovalRule(MC.OETH, MC.WOETH));
            RulesVerification.verifyProcessorRule(withdrawer, BaseRules.getDepositRule(MC.WOETH, address(withdrawer)));
            RulesVerification.verifyProcessorRule(withdrawer, BaseRules.getWithdrawRule(MC.WOETH, address(withdrawer)));
            RulesVerification.verifyProcessorRule(withdrawer, BaseRules.getRedeemRule(MC.WOETH, address(withdrawer)));
        }

        {
            // mint oeth with weth
            RulesVerification.verifyProcessorRule(withdrawer, BaseRules.getApprovalRule(MC.WETH, MC.OETH_VAULT));
            RulesVerification.verifyProcessorRule(withdrawer, OriginRules.getMintRule(MC.OETH_VAULT, MC.WETH));
        }
    }

    function verifyRules(IVault vault) internal view {
        Withdrawer withdrawer = getWithdrawer(vault);

        {
            // Verify WETH approvals
            address[] memory wethSpenders = new address[](3);
            wethSpenders[0] = MC.EULER_WETH_22_VAULT;
            wethSpenders[1] = address(withdrawer);
            wethSpenders[2] = MC.OETH_VAULT;

            RulesVerification.verifyProcessorRule(vault, BaseRules.getApprovalRule(MC.WETH, wethSpenders));
        }

        {
            // verify weth deposit/withdraw rules
            RulesVerification.verifyProcessorRule(vault, BaseRules.getWethDepositRule(MC.WETH));
            RulesVerification.verifyProcessorRule(vault, BaseRules.getWethWithdrawRule(MC.WETH));
        }

        {
            // ynETH rules
            RulesVerification.verifyProcessorRule(vault, YieldNestRules.getYnETHDepositRule(MC.YNETH, address(vault)));
        }

        {
            // ynLSDe rules
            address[] memory depositAssets = new address[](2);
            depositAssets[0] = MC.WSTETH;
            depositAssets[1] = MC.WOETH;

            RulesVerification.verifyProcessorRule(
                vault, YieldNestRules.getYnEigenDepositRule(MC.YNLSDE, depositAssets, address(vault))
            );
        }

        {
            // approvals for wstETH
            address[] memory strategies = new address[](3);
            strategies[0] = MC.YNLSDE;
            strategies[1] = address(withdrawer);
            strategies[2] = MC.SMOKEHOUSE_WSTETH;

            RulesVerification.verifyProcessorRule(vault, BaseRules.getApprovalRule(MC.WSTETH, strategies));
        }

        {
            // approvals for stETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.WSTETH;
            strategies[1] = address(withdrawer);

            RulesVerification.verifyProcessorRule(vault, BaseRules.getApprovalRule(MC.STETH, strategies));
        }

        {
            // approvals for woETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.YNLSDE;
            strategies[1] = address(withdrawer);

            RulesVerification.verifyProcessorRule(vault, BaseRules.getApprovalRule(MC.WOETH, strategies));
        }

        {
            // approvals for oETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.WOETH;
            strategies[1] = address(withdrawer);

            RulesVerification.verifyProcessorRule(vault, BaseRules.getApprovalRule(MC.OETH, strategies));
        }

        {
            // Curve LP Strategy rules
            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getApprovalRule(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR)
            );
            RulesVerification.verifyProcessorRule(
                vault, ConnectorRules.getConnectorDepositRule(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR)
            );
            RulesVerification.verifyProcessorRule(
                vault, ConnectorRules.getConnectorWithdrawRule(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR)
            );
        }

        // Withdrawer rules
        {
            // Verify deposit rules for all assets
            address[] memory assets = new address[](9);
            uint256 index = 0;

            assets[index++] = MC.WETH;
            assets[index++] = MC.YNETH;
            assets[index++] = MC.YNLSDE;
            assets[index++] = MC.WOETH;
            assets[index++] = MC.OETH;
            assets[index++] = MC.WSTETH;
            assets[index++] = MC.STETH;
            assets[index++] = MC.METH;
            assets[index++] = MC.SFRXETH;

            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getDepositAssetRule(address(withdrawer), assets, address(vault))
            );
            // Verify withdraw rules
            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getWithdrawAssetRule(address(withdrawer), MC.WETH, address(vault))
            );
        }

        {
            // Verify buffer rules
            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getDepositRule(MC.EULER_WETH_22_VAULT, address(vault))
            );
            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getWithdrawRule(MC.EULER_WETH_22_VAULT, address(vault))
            );
        }

        {
            // Verify submit rule on stETH
            RulesVerification.verifyProcessorRule(vault, StakedEtherRules.getSubmitRule(MC.STETH, address(vault)));
            // Verify wstETH wrap/unwrap rules
            RulesVerification.verifyProcessorRule(vault, StakedEtherRules.getWrapRule(MC.WSTETH));
            RulesVerification.verifyProcessorRule(vault, StakedEtherRules.getUnwrapRule(MC.WSTETH));
        }

        {
            // Verify woETH deposit/withdraw/redeem rules
            RulesVerification.verifyProcessorRule(vault, BaseRules.getDepositRule(MC.WOETH, address(vault)));
            RulesVerification.verifyProcessorRule(vault, BaseRules.getWithdrawRule(MC.WOETH, address(vault)));
            RulesVerification.verifyProcessorRule(vault, BaseRules.getRedeemRule(MC.WOETH, address(vault)));
        }

        {
            // Verify smoke house deposit/withdraw/redeem rules
            RulesVerification.verifyProcessorRule(vault, BaseRules.getDepositRule(MC.SMOKEHOUSE_WSTETH, address(vault)));
            RulesVerification.verifyProcessorRule(
                vault, BaseRules.getWithdrawRule(MC.SMOKEHOUSE_WSTETH, address(vault))
            );
            RulesVerification.verifyProcessorRule(vault, BaseRules.getRedeemRule(MC.SMOKEHOUSE_WSTETH, address(vault)));
        }

        {
            // mint oeth with weth
            RulesVerification.verifyProcessorRule(withdrawer, OriginRules.getMintRule(MC.OETH_VAULT, MC.WETH));
        }
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
    }
}
