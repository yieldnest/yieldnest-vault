// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IActors} from "script/Actors.sol";
import {FxProtocolRules} from "script/rules/FxProtocolRules.sol";

library WithdrawerConfig {
    error InvalidRules();

    string public constant WITHDRAWER_SYMBOL = "ynUSDxWithdrawer";

    function configure(Withdrawer vault, address provider, address timelock, address deployer, IActors actors)
        internal
    {
        {
            // initialize
            string memory name = "ynUSDx Withdrawer";
            string memory symbol = WITHDRAWER_SYMBOL;
            uint8 decimals_ = 18;
            bool countNativeAsset_ = false;
            bool alwaysComputeTotalAssets_ = false;
            uint256 defaultAssetIndex_ = 1;

            vault.initialize(
                deployer, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_, defaultAssetIndex_
            );
        }

        {
            // configure roles
            BaseRoles.configureDefaultRoles(vault, timelock, actors);
            vault.grantRole(vault.ALLOCATOR_ROLE(), MC.YNUSDx);
            vault.grantRole(vault.ALLOCATOR_ROLE(), actors.BOOTSTRAPPER());
            BaseRoles.configureTemporaryRoles(vault, deployer);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WRAPPED_USDC, true, true);
            // DEFAULT asset is second.
            vault.addAsset(MC.USDC, true, true);
            vault.addAsset(MC.FXUSD, true, true);
            vault.addAsset(MC.FXBASE, true, true);
            vault.addAsset(MC.FXSAVE, true, true);
        }

        // Rules for ynUSDx Withdrawer
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        uint256 ruleIndex = 0;

        rules[ruleIndex++] = FxProtocolRules.getFxUSDSavePoolRequestRedeemRule(MC.FXSAVE);
        rules[ruleIndex++] = FxProtocolRules.getFxUSDSavePoolRedeemRule(MC.FXSAVE, address(vault));

        if (ruleIndex != rules.length) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(vault, rules, true);

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault, deployer);
    }

    // Helper: allowlist for FXBASE deposit tokens (USDC, FXUSD)
    function _fxBaseDepositTokenAllowList() private pure returns (address[] memory list) {
        list = new address[](2);
        list[0] = MC.USDC;
        list[1] = MC.FXUSD;
    }

    // Helper: allowlist for FXSAVE deposit tokens (FXUSD)
    function _fxSaveDepositTokenAllowList() private pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = MC.FXUSD;
    }
}
