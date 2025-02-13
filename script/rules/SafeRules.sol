// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

library SafeRules {
    error RuleAlreadyExists();

    struct RuleParams {
        address contractAddress;
        bytes4 funcSig;
        IVault.FunctionRule rule;
    }

    function setProcessorRule(IVault vault_, RuleParams memory params) internal {
        setProcessorRule(vault_, params, false);
    }

    function setProcessorRule(IVault vault_, RuleParams memory params, bool force) internal {
        if (force) {
            vault_.setProcessorRule(params.contractAddress, params.funcSig, params.rule);
            return;
        }
        IVault.FunctionRule memory existingRule = vault_.getProcessorRule(params.contractAddress, params.funcSig);
        if (
            existingRule.isActive || address(existingRule.validator) != address(0) || existingRule.paramRules.length > 0
        ) {
            revert RuleAlreadyExists();
        }
        vault_.setProcessorRule(params.contractAddress, params.funcSig, params.rule);
    }

    function setProcessorRules(IVault vault_, RuleParams[] memory params) internal {
        setProcessorRules(vault_, params, false);
    }

    function setProcessorRules(IVault vault_, RuleParams[] memory params, bool force) internal {
        if (force) {
            address[] memory contractAddresses = new address[](params.length);
            bytes4[] memory funcSigs = new bytes4[](params.length);
            IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](params.length);
            for (uint256 i = 0; i < params.length; i++) {
                contractAddresses[i] = params[i].contractAddress;
                funcSigs[i] = params[i].funcSig;
                rules[i] = params[i].rule;
            }

            vault_.setProcessorRules(contractAddresses, funcSigs, rules);
            return;
        }
        for (uint256 i = 0; i < params.length; i++) {
            setProcessorRule(vault_, params[i], false);
        }
    }

    function generateCalldata(RuleParams[] memory rules_) internal pure returns (bytes memory) {
        address[] memory contractsAddresses = new address[](rules_.length);
        bytes4[] memory funcSigs = new bytes4[](rules_.length);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](rules_.length);

        for (uint256 i = 0; i < rules_.length; i++) {
            contractsAddresses[i] = rules_[i].contractAddress;
            funcSigs[i] = rules_[i].funcSig;
            rules[i] = rules_[i].rule;
        }

        return abi.encodeWithSelector(IVault.setProcessorRules.selector, contractsAddresses, funcSigs, rules);
    }

    function generateCalldata(RuleParams memory ruleParams) internal pure returns (bytes memory) {
        return generateCalldata(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
    }

    function generateCalldata(address contractAddress, bytes4 funcSig, IVault.FunctionRule memory rule)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IVault.setProcessorRule.selector, contractAddress, funcSig, rule);
    }
}
