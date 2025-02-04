// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {YieldNestRules} from "script/rules/YieldNestRules.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {IVault} from "src/interface/IVault.sol";

contract YnETHxConfigurer is MainnetActors {
    error NotAdmin();
    error InvalidVaultVersion();

    function configure(address provider, address withdrawer) external {
        YnETHxVault vault = YnETHxVault(payable(MC.YNETHX));
        if (!vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this))) {
            revert NotAdmin();
        }
        if (keccak256(bytes(vault.VAULT_VERSION())) != keccak256(bytes("0.2.0"))) {
            revert InvalidVaultVersion();
        }

        {
            // configure roles
            BaseRoles.configureDefaultRoles(vault, MC.TIMELOCK, IActors(address(this)));
            vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
            BaseRoles.configureTemporaryRoles(vault);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        // set the buffer
        vault.setBuffer(MC.EULER_WETH_22_VAULT);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WETH, true);
            vault.addAsset(MC.YNETH, true);
            vault.addAsset(MC.YNLSDE, true);
            vault.addAsset(MC.STETH, true);

            vault.addAsset(MC.EULER_WETH_22_VAULT, false); // buffer
            vault.addAsset(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, false);
            vault.addAsset(MC.WSTETH, false);
            vault.addAsset(MC.OETH, false);
            vault.addAsset(MC.WOETH, false);
            vault.addAsset(withdrawer, false);
        }

        {
            // wrap/unwrap ETH
            BaseRules.RuleParams memory wethDepositRuleParams = BaseRules.getWethDepositRule(vault, MC.WETH);
            SafeRules.setProcessorRule(
                vault, wethDepositRuleParams.contractAddress, wethDepositRuleParams.funcSig, wethDepositRuleParams.rule
            );
            BaseRules.RuleParams memory wethWithdrawRuleParams = BaseRules.getWethWithdrawRule(vault, MC.WETH);
            SafeRules.setProcessorRule(
                vault,
                wethWithdrawRuleParams.contractAddress,
                wethWithdrawRuleParams.funcSig,
                wethWithdrawRuleParams.rule
            );
        }

        {
            // approvals for WETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.EULER_WETH_22_VAULT;
            strategies[1] = withdrawer;
            BaseRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(vault, MC.WETH, strategies);
            SafeRules.setProcessorRule(
                vault, approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule
            );
        }

        {
            // approvals for wstETH and woETH
            address[] memory assets = new address[](2);
            assets[0] = MC.WSTETH;
            assets[1] = MC.WOETH;

            address[] memory strategies = new address[](2);
            strategies[0] = MC.YNLSDE;
            strategies[1] = withdrawer;

            for (uint256 i = 0; i < assets.length; i++) {
                BaseRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(vault, assets[i], strategies);
                SafeRules.setProcessorRule(
                    vault, approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule
                );
            }
        }

        {
            // buffer deposit/withdraw WETH
            // getApprovalRule(vault, MC.WETH, MC.EULER_WETH_22_VAULT);
            BaseRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(vault, MC.EULER_WETH_22_VAULT);
            SafeRules.setProcessorRule(
                vault, depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule
            );
            BaseRules.RuleParams memory withdrawRuleParams = BaseRules.getWithdrawRule(vault, MC.EULER_WETH_22_VAULT);
            SafeRules.setProcessorRule(
                vault, withdrawRuleParams.contractAddress, withdrawRuleParams.funcSig, withdrawRuleParams.rule
            );
        }

        {
            // depositETH on ynETH
            YieldNestRules.setYnETHDepositRule(vault, MC.YNETH, address(vault));
        }

        {
            // deposit(asset, amount, receiver) for wstETH and woETH to ynLSDe
            address[] memory assets = new address[](2);
            assets[0] = MC.WSTETH;
            assets[1] = MC.WOETH;
            // for (uint256 i = 0; i < assets.length; i++) {
            //     getApprovalRule(vault, assets[i], MC.YNLSDE);
            // }
            YieldNestRules.setYnEigenDepositRule(vault, MC.YNLSDE, assets, address(vault));
        }

        {
            // approvals for ynETH and ynLSDe
            address[] memory assets = new address[](2);
            assets[0] = MC.YNETH;
            assets[1] = MC.YNLSDE;

            address[] memory strategies = new address[](2);
            strategies[0] = MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR;
            strategies[1] = withdrawer;

            for (uint256 i = 0; i < assets.length; i++) {
                BaseRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(vault, assets[i], strategies);
                vault.setProcessorRule(
                    approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule
                );
            }
        }

        {
            // ynETH-ynLSDe pool connector & tokenized strategy
            // getApprovalRule(vault, MC.YNETH, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            // getApprovalRule(vault, MC.YNLSDE, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            BaseRules.RuleParams memory ynLsDeRuleParams =
                BaseRules.getApprovalRule(vault, MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            SafeRules.setProcessorRule(
                vault, ynLsDeRuleParams.contractAddress, ynLsDeRuleParams.funcSig, ynLsDeRuleParams.rule
            );
            ConnectorRules.setConnectorDepositRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            ConnectorRules.setConnectorWithdrawRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        }

        {
            // withdrawer deposit all assets and withdraw WETH
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

            for (uint256 i = 0; i < assets.length; i++) {
                if (
                    assets[i] == MC.WETH || assets[i] == MC.WSTETH || assets[i] == MC.WOETH || assets[i] == MC.YNETH
                        || assets[i] == MC.YNLSDE
                ) {
                    continue;
                }
                BaseRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(vault, assets[i], withdrawer);
                vault.setProcessorRule(
                    approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule
                );
            }
            BaseRules.RuleParams memory depositRuleParams = BaseRules.getDepositAssetRule(vault, withdrawer, assets);
            vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);

            // Withdrawable: only WETH
            BaseRules.RuleParams memory withdrawerRuleParams = BaseRules.getWithdrawRule(vault, withdrawer);
            vault.setProcessorRule(
                withdrawerRuleParams.contractAddress, withdrawerRuleParams.funcSig, withdrawerRuleParams.rule
            );
            BaseRules.RuleParams memory withdrawAssetRuleParams =
                BaseRules.getWithdrawAssetRule(vault, withdrawer, MC.WETH);
            vault.setProcessorRule(
                withdrawAssetRuleParams.contractAddress, withdrawAssetRuleParams.funcSig, withdrawAssetRuleParams.rule
            );
        }

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault);
    }
}
