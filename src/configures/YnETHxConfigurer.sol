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
            (address weth_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                BaseRules.getWethDepositRule(vault, MC.WETH);
            SafeRules.setProcessorRule(vault, weth_, funcSig, rule);
            (weth_, funcSig, rule) = BaseRules.getWethWithdrawRule(vault, MC.WETH);
            SafeRules.setProcessorRule(vault, weth_, funcSig, rule);
        }

        {
            // approvals for WETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.EULER_WETH_22_VAULT;
            strategies[1] = withdrawer;
            (address weth_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                BaseRules.getApprovalRule(vault, MC.WETH, strategies);
            SafeRules.setProcessorRule(vault, weth_, funcSig, rule);
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
                (address asset_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                    BaseRules.getApprovalRule(vault, assets[i], strategies);
                SafeRules.setProcessorRule(vault, asset_, funcSig, rule);
            }
        }

        {
            // buffer deposit/withdraw WETH
            // getApprovalRule(vault, MC.WETH, MC.EULER_WETH_22_VAULT);
            (address eulerWeth_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                BaseRules.getDepositRule(vault, MC.EULER_WETH_22_VAULT);
            SafeRules.setProcessorRule(vault, eulerWeth_, funcSig, rule);
            (eulerWeth_, funcSig, rule) = BaseRules.getWithdrawRule(vault, MC.EULER_WETH_22_VAULT);
            SafeRules.setProcessorRule(vault, eulerWeth_, funcSig, rule);
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
                (address asset_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                    BaseRules.getApprovalRule(vault, assets[i], strategies);
                vault.setProcessorRule(asset_, funcSig, rule);
            }
        }

        {
            // ynETH-ynLSDe pool connector & tokenized strategy
            // getApprovalRule(vault, MC.YNETH, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            // getApprovalRule(vault, MC.YNLSDE, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            (address ynLsDe_, bytes4 funcSig, IVault.FunctionRule memory rule) =
                BaseRules.getApprovalRule(vault, MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            SafeRules.setProcessorRule(vault, ynLsDe_, funcSig, rule);
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
                (address asset_, bytes4 approvalFuncSig, IVault.FunctionRule memory approvalRule) =
                    BaseRules.getApprovalRule(vault, assets[i], withdrawer);
                vault.setProcessorRule(asset_, approvalFuncSig, approvalRule);
            }
            (address withdrawer_, bytes4 depositFuncSig, IVault.FunctionRule memory depositRule) =
                BaseRules.getDepositAssetRule(vault, withdrawer, assets);
            vault.setProcessorRule(withdrawer_, depositFuncSig, depositRule);

            // Withdrawable: only WETH
            (address withdrawer__, bytes4 withdrawFuncSig, IVault.FunctionRule memory withdrawRule) =
                BaseRules.getWithdrawRule(vault, withdrawer);
            vault.setProcessorRule(withdrawer__, withdrawFuncSig, withdrawRule);
            (withdrawer__, withdrawFuncSig, withdrawRule) = BaseRules.getWithdrawAssetRule(vault, withdrawer, MC.WETH);
            vault.setProcessorRule(withdrawer__, withdrawFuncSig, withdrawRule);
        }

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault);
    }
}
