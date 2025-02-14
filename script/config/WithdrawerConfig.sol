// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {OriginRules} from "script/rules/OriginRules.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {StakedEtherRules} from "script/rules/StakedEtherRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IActors} from "script/Actors.sol";

library WithdrawerConfig {
    error InvalidRules();

    string public constant WITHDRAWER_SYMBOL = "ynETHxWithdrawer";

    function configure(Withdrawer vault, address provider, address timelock, address deployer, IActors actors)
        internal
    {
        {
            // initialize
            string memory name = "ynETH MAX Withdrawer";
            string memory symbol = WITHDRAWER_SYMBOL;
            uint8 decimals_ = 18;
            bool countNativeAsset_ = true;
            bool alwaysComputeTotalAssets_ = false;

            vault.initialize(deployer, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
        }

        {
            // configure roles
            BaseRoles.configureDefaultRoles(vault, timelock, actors);
            vault.grantRole(vault.ALLOCATOR_ROLE(), MC.YNETHX);
            vault.grantRole(vault.ALLOCATOR_ROLE(), actors.BOOTSTRAPPER());
            BaseRoles.configureTemporaryRoles(vault, deployer);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WETH, true, true);
            vault.addAsset(MC.STETH, true, false);
            vault.addAsset(MC.WSTETH, true, false);
            vault.addAsset(MC.METH, true, false);
            vault.addAsset(MC.WOETH, true, false);
            vault.addAsset(MC.OETH, true, false);
            vault.addAsset(MC.SFRXETH, true, false);
            vault.addAsset(MC.YNLSDE, true, false);
            vault.addAsset(MC.YNETH, true, false);
        }

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](17);
        uint256 ruleIndex = 0;

        {
            // ynETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, address(vault));
        }

        {
            // ynLSDe withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, address(vault));
        }

        {
            // wstETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
            rules[ruleIndex++] =
                WithdrawerRules.getRequestWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(vault));
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(vault));
        }

        // NOTE: woeth withdrawal is handled via direct methods on the vault

        {
            // wrap/unwrap wstETH
            rules[ruleIndex++] = StakedEtherRules.getWrapRule(MC.WSTETH);
            rules[ruleIndex++] = StakedEtherRules.getUnwrapRule(MC.WSTETH);
        }

        {
            // wrap/unwrap woeth
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.OETH, MC.WOETH);
            rules[ruleIndex++] = BaseRules.getDepositRule(MC.WOETH, address(vault));
            rules[ruleIndex++] = BaseRules.getWithdrawRule(MC.WOETH, address(vault));
            rules[ruleIndex++] = BaseRules.getRedeemRule(MC.WOETH, address(vault));
        }

        {
            // mint oeth with weth
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.WETH, MC.OETH_VAULT);
            rules[ruleIndex++] = OriginRules.getMintRule(MC.OETH_VAULT, MC.WETH);
        }

        if (ruleIndex != rules.length) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(vault, rules, true);

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }
}
