// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IActors} from "script/Actors.sol";
import {FxProtocolRules} from "script/rules/FxProtocolRules.sol";
import {IVault} from "src/interface/IVault.sol";

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

        rules[ruleIndex++] = FxProtocolRules.getFxUSDSavePoolRequestRedeemRule(MC.FXBASE);
        rules[ruleIndex++] = FxProtocolRules.getFxUSDSavePoolRedeemRule(MC.FXBASE, address(vault));

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

    function getMaxVaultRulesConfiguration(IVault vault, IVault withdrawer)
        internal
        view
        returns (SafeRules.RuleParams[] memory rules)
    {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](10);
        uint256 i = 0;

        // Set approval rule for USDC to allow only FXBASE and withdrawer as spenders
        address[] memory usdcSpender = new address[](2);
        usdcSpender[0] = MC.FXBASE;
        usdcSpender[1] = address(withdrawer);
        rules[i++] = BaseRules.getAppendApprovalRule(MC.USDC, usdcSpender, vault);

        // Set deposit rule for FXBASE with USDC as token in allow list
        address[] memory fxBaseTokenInAllowList = new address[](1);
        fxBaseTokenInAllowList[0] = MC.USDC;
        rules[i++] = FxProtocolRules.getFxUSDSavePoolDepositRule(MC.FXBASE, address(vault), fxBaseTokenInAllowList);

        // Set approval rule for FXBASE to allow only FXSAVE and withdrawer as spenders
        address[] memory fxBaseSpenderAllowList = new address[](2);
        fxBaseSpenderAllowList[0] = MC.FXSAVE;
        fxBaseSpenderAllowList[1] = address(withdrawer);
        rules[i++] = BaseRules.getApprovalRule(MC.FXBASE, fxBaseSpenderAllowList);

        // Set deposit rule for FXSAVE
        rules[i++] = BaseRules.getDepositRule(MC.FXSAVE, address(vault));

        // Set redeem rule for FXSAVE
        rules[i++] = BaseRules.getRedeemRule(MC.FXSAVE, address(vault));

        // Set deposit and withdraw asset rules for withdrawer and FXBASE
        rules[i++] = BaseRules.getDepositAssetRule(address(withdrawer), MC.FXBASE, address(vault));

        rules[i++] = BaseRules.getDepositRule(address(withdrawer), address(vault));

        // Set withdraw rule for USDC for withdrawer
        rules[i++] = BaseRules.getWithdrawRule(address(withdrawer), address(vault));

        rules[i++] = BaseRules.getWithdrawAssetRule(address(withdrawer), MC.FXUSD, address(vault));

        rules[i++] = BaseRules.getApprovalRule(MC.FXUSD, MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER);

        if (i != rules.length) {
            revert InvalidRules();
        }

        return rules;
    }
}
