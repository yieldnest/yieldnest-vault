// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

library SafeRules {
    error RuleAlreadyExists();

    function setProcessorRule(IVault vault_, address contractAddress, bytes4 funcSig, IVault.FunctionRule memory rule)
        internal
    {
        setProcessorRule(vault_, contractAddress, funcSig, rule, false);
    }

    function setProcessorRule(
        IVault vault_,
        address contractAddress,
        bytes4 funcSig,
        IVault.FunctionRule memory rule,
        bool force
    ) internal {
        if (force) {
            vault_.setProcessorRule(contractAddress, funcSig, rule);
            return;
        }
        IVault.FunctionRule memory existingRule = vault_.getProcessorRule(contractAddress, funcSig);
        if (
            existingRule.isActive || address(existingRule.validator) != address(0) || existingRule.paramRules.length > 0
        ) {
            revert RuleAlreadyExists();
        }
        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }
}
