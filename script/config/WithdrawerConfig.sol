// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IActors} from "script/Actors.sol";

library WithdrawerConfig {
    error InvalidRules();

    string public constant WITHDRAWER_SYMBOL = "ynBNBxWithdrawer";

    function configure(Withdrawer vault, address provider, address timelock, address deployer, IActors actors)
        internal
    {
        {
            // initialize
            string memory name = "ynBNB MAX Withdrawer";
            string memory symbol = WITHDRAWER_SYMBOL;
            uint8 decimals_ = 18;
            bool countNativeAsset_ = true;
            bool alwaysComputeTotalAssets_ = false;
            uint256 defaultAssetIndex = 0;

            vault.initialize(
                deployer, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_, defaultAssetIndex
            );
        }

        {
            // configure roles
            BaseRoles.configureDefaultRoles(vault, timelock, actors);
            vault.grantRole(vault.ALLOCATOR_ROLE(), MC.YNBNBX);
            vault.grantRole(vault.ALLOCATOR_ROLE(), actors.BOOTSTRAPPER());
            BaseRoles.configureTemporaryRoles(vault, deployer);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        // Add assets: Base asset always first
        vault.addAsset(MC.WBNB, true);
        vault.addAsset(MC.YNBNBK, true);
        vault.addAsset(MC.BNBX, true);
        vault.addAsset(MC.SLISBNB, true);

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](3);
        uint256 i = 0;

        // setup processor rules for the withdrawer
        rules[i++] = WithdrawerRules.getRequestWithdrawRule(MC.SLIS_BNB_STAKE_MANAGER);
        rules[i++] = WithdrawerRules.getClaimWithdrawRule(MC.SLIS_BNB_STAKE_MANAGER);
        rules[i++] = BaseRules.getApprovalRule(MC.SLISBNB, MC.SLIS_BNB_STAKE_MANAGER);

        if (i != rules.length) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(vault, rules, true);

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }
}
