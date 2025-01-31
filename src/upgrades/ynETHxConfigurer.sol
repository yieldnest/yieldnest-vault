// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {ynETHxVault} from "src/ynETHxVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {ConnectorRules} from "script/rules/ConnectorRules.sol";
import {Provider} from "src/module/Provider.sol";

contract ynETHxConfigurer is BaseRules, ConnectorRules, MainnetActors {
    error NotAdmin();

    function upgrade() public {
        Vault vault = Vault(payable(MC.YNETHX));

        if (!vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this))) {
            revert NotAdmin();
        }

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true);
        vault.addAsset(MC.YNETH, true);
        vault.addAsset(MC.YNLSDE, true);

        vault.addAsset(MC.EULER_WETH_22_VAULT, false); // buffer
        vault.addAsset(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, false);
        vault.addAsset(MC.WSTETH, false);
        vault.addAsset(MC.WOETH, false);
        vault.addAsset(MC.WITHDRAWER, false);

        // wrap/unwrap ETH
        setWethDepositRule(vault, MC.WETH);
        setWethWithdrawRule(vault, MC.WETH);

        setApprovalRule(vault, MC.WETH, MC.EULER_WETH_22_VAULT);
        setDepositRule(vault, MC.EULER_WETH_22_VAULT, address(vault)); // buffer
        // add withdraw rule for buffer too

        // fix this to call depositETH function on ynETH (uses payable ether rather than WETH)
        setDepositRule(vault, MC.YNETH, address(vault));

        // fix this to call deposit(asset, amount, receiver) on ynLSDe
        // also add approvals for wstETH and woETH to ynLSDe
        setDepositRule(vault, MC.YNLSDE, address(vault));

        // rules for connector & tokenized strategy
        setApprovalRule(vault, MC.YNETH, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        setApprovalRule(vault, MC.YNLSDE, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        setConnectorDepositRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);
        setConnectorWithdrawRule(vault, MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR);

        // add rules for transfering / depositing all assets into the withdrawer
        // also rules for withdrawing WETH from the withdrawer

        vault.setProvider(MC.PROVIDER); // TODO: deploy provider first
        vault.setBuffer(MC.EULER_WETH_22_VAULT);

        vault.unpause();

        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
    }
}
