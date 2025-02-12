// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {SafeRules} from "script/rules/SafeRules.sol";

library RulesVerification {
    function verifyProcessorRule(IVault vault_, SafeRules.RuleParams memory rule) public view {
        verifyProcessorRule(vault_, rule.contractAddress, rule.funcSig, rule.rule);
    }

    function verifyProcessorRule(
        IVault vault_,
        address contractAddress,
        bytes4 funcSig,
        IVault.FunctionRule memory expectedResult
    ) public view {
        IVault.FunctionRule memory rule = vault_.getProcessorRule(contractAddress, funcSig);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // Add assertions
        vm.assertEq(rule.isActive, expectedResult.isActive, "isActive does not match");
        vm.assertEq(rule.paramRules.length, expectedResult.paramRules.length, "paramRules length does not match");

        for (uint256 i = 0; i < rule.paramRules.length; i++) {
            vm.assertEq(
                uint256(rule.paramRules[i].paramType),
                uint256(expectedResult.paramRules[i].paramType),
                "paramType does not match"
            );
            vm.assertEq(rule.paramRules[i].isArray, expectedResult.paramRules[i].isArray, "isArray does not match");
            vm.assertEq(
                rule.paramRules[i].allowList.length,
                expectedResult.paramRules[i].allowList.length,
                "allowList length does not match"
            );

            for (uint256 j = 0; j < rule.paramRules[i].allowList.length; j++) {
                vm.assertEq(
                    rule.paramRules[i].allowList[j],
                    expectedResult.paramRules[i].allowList[j],
                    "allowList element does not match"
                );
            }
        }
    }
}
