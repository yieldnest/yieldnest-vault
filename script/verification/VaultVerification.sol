// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {YieldNestRules} from "script/rules/YieldNestRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

library VaultVerification {
    function verifyVaultConfiguration(Vault vault, Withdrawer withdrawer) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Verify core vault configuration
        vm.assertEq(vault.alwaysComputeTotalAssets(), false);
        vm.assertEq(vault.countNativeAsset(), true);
        vm.assertEq(vault.decimals(), 18);
        vm.assertEq(vault.baseWithdrawalFee(), 1e5); // 0.1%

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

        address[] memory inactiveAssets = new address[](5);
        inactiveAssets[0] = MC.EULER_WETH_22_VAULT;
        inactiveAssets[1] = MC.CURVE_LP_YNETH_YNLSDE_STRATEGY;
        inactiveAssets[2] = address(withdrawer);
        inactiveAssets[3] = MC.WSTETH;
        inactiveAssets[4] = MC.WOETH;

        for (uint256 i = 0; i < inactiveAssets.length; i++) {
            IVault.AssetParams memory asset = vault.getAsset(inactiveAssets[i]);
            vm.assertFalse(asset.active);
            vm.assertEq(asset.decimals, 18);
        }

        // Verify total number of assets
        address[] memory assets = vault.getAssets();
        // WETH, YNETH, YNLSDE, EULER_WETH_22_VAULT, CURVE_LP_YNETH_YNLSDE_STRATEGY, withdrawer, WSTETH, WOETH, STETH, OETH
        vm.assertEq(assets.length, 10);

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

        // Base asset should always be 1:1
        vm.assertEq(provider.getRate(MC.WETH), 1e18, "WETH rate should be 1:1");
    }

    function verifyWithdrawerConfiguration(Vault vault, Withdrawer withdrawer) internal {
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

    function verifyRules(IVault vault) internal view {
        Withdrawer withdrawer = getWithdrawer(vault);

        {
            SafeRules.RuleParams memory depositParams = BaseRules.getWethDepositRule(MC.WETH);
            RulesVerification.verifyProcessorRule(
                vault, depositParams.contractAddress, depositParams.funcSig, depositParams.rule
            );

            SafeRules.RuleParams memory withdrawParams = BaseRules.getWethWithdrawRule(MC.WETH);
            RulesVerification.verifyProcessorRule(
                vault, withdrawParams.contractAddress, withdrawParams.funcSig, withdrawParams.rule
            );
        }

        {
            // ynETH rules
            SafeRules.RuleParams memory params = YieldNestRules.getYnETHDepositRule(MC.YNETH, address(vault));
            RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
        }

        {
            // ynLSDe rules
            address[] memory depositAssets = new address[](2);
            depositAssets[0] = MC.WSTETH;
            depositAssets[1] = MC.WOETH;

            SafeRules.RuleParams memory params =
                YieldNestRules.getYnEigenDepositRule(MC.YNLSDE, depositAssets, address(vault));
            RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
        }
        {
            // Approve rules for deposit assets
            address[] memory spenders = new address[](2);
            spenders[0] = MC.YNLSDE;
            spenders[1] = address(withdrawer);

            SafeRules.RuleParams memory wstethParams = BaseRules.getApprovalRule(MC.WSTETH, spenders);
            RulesVerification.verifyProcessorRule(
                vault, wstethParams.contractAddress, wstethParams.funcSig, wstethParams.rule
            );

            SafeRules.RuleParams memory woethParams = BaseRules.getApprovalRule(MC.WOETH, spenders);
            RulesVerification.verifyProcessorRule(
                vault, woethParams.contractAddress, woethParams.funcSig, woethParams.rule
            );
        }

        // Curve LP Strategy rules
        {
            {
                SafeRules.RuleParams memory params =
                    BaseRules.getApprovalRule(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
                RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
            }

            {
                SafeRules.RuleParams memory params =
                    ConnectorRules.getConnectorDepositRule(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
                RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
            }

            {
                SafeRules.RuleParams memory params =
                    ConnectorRules.getConnectorWithdrawRule(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
                RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
            }
        }

        // Withdrawer rules
        {
            // Verify deposit rules for all assets
            address[] memory assets = new address[](10);
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

            {
                SafeRules.RuleParams memory params =
                    BaseRules.getDepositAssetRule(address(withdrawer), assets, address(vault));
                RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
            }

            {
                // Verify withdraw rules
                SafeRules.RuleParams memory params =
                    BaseRules.getWithdrawAssetRule(address(withdrawer), MC.WETH, address(vault));
                RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
            }
        }

        // Verify buffer rules
        {
            // Verify deposit rule
            SafeRules.RuleParams memory params = BaseRules.getDepositRule(MC.EULER_WETH_22_VAULT, address(vault));
            RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
        }

        {
            // Verify withdraw rule
            SafeRules.RuleParams memory params = BaseRules.getWithdrawRule(MC.EULER_WETH_22_VAULT, address(vault));
            RulesVerification.verifyProcessorRule(vault, params.contractAddress, params.funcSig, params.rule);
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
        revert("Withdrawer not found");
    }
}
