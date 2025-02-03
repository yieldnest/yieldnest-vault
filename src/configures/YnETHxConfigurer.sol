// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {YieldNestRules} from "script/rules/YieldNestRules.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";

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
            BaseRules.setWethDepositRule(vault, MC.WETH);
            BaseRules.setWethWithdrawRule(vault, MC.WETH);
        }

        {
            // approvals for WETH
            address[] memory strategies = new address[](2);
            strategies[0] = MC.EULER_WETH_22_VAULT;
            strategies[1] = withdrawer;
            BaseRules.setApprovalRule(vault, MC.WETH, strategies);
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
                BaseRules.setApprovalRule(vault, assets[i], strategies);
            }
        }

        {
            // buffer deposit/withdraw WETH
            // setApprovalRule(vault, MC.WETH, MC.EULER_WETH_22_VAULT);
            BaseRules.setDepositRule(vault, MC.EULER_WETH_22_VAULT);
            BaseRules.setWithdrawRule(vault, MC.EULER_WETH_22_VAULT);
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
            //     setApprovalRule(vault, assets[i], MC.YNLSDE);
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
                BaseRules.setApprovalRule(vault, assets[i], strategies);
            }
        }

        {
            // ynETH-ynLSDe pool connector & tokenized strategy
            // setApprovalRule(vault, MC.YNETH, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            // setApprovalRule(vault, MC.YNLSDE, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
            BaseRules.setApprovalRule(vault, MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
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
                BaseRules.setApprovalRule(vault, assets[i], withdrawer);
            }
            BaseRules.setDepositAssetRule(vault, withdrawer, assets);

            // Withdrawable: only WETH
            BaseRules.setWithdrawRule(vault, withdrawer);
            BaseRules.setWithdrawAssetRule(vault, withdrawer, MC.WETH);
        }

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault);
    }
}
