// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {BaseRuleUtils} from "./BaseRuleUtils.sol";

contract RuleUtils is BaseRuleUtils {
    function getSlisDepositRule(address contractAddress) public pure returns (RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("deposit()"));
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams(contractAddress, funcSig, rule);
    }

    function getAstherusMintRule(address contractAddress) public pure returns (RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("mintAsBnb(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams(contractAddress, funcSig, rule);
    }

    function getApprovalRuleAppendToExistingSpenders(address targetVault, address token, address[] memory newSpenders)
        public
        view
        returns (RuleParams memory)
    {
        // Get existing spenders from current rule
        IVault vault = IVault(targetVault);
        IVault.FunctionRule memory rule = vault.getProcessorRule(token, bytes4(keccak256("approve(address,uint256)")));

        // If no existing rule or not active, just use new spenders
        if (!rule.isActive || rule.paramRules.length == 0) {
            return getApprovalRule(token, newSpenders);
        }

        // Get existing allowed spenders
        address[] memory existingSpenders = rule.paramRules[0].allowList;

        // Combine existing and new spenders
        address[] memory allSpenders = new address[](existingSpenders.length + newSpenders.length);
        for (uint256 i = 0; i < existingSpenders.length; i++) {
            allSpenders[i] = existingSpenders[i];
        }
        for (uint256 i = 0; i < newSpenders.length; i++) {
            allSpenders[existingSpenders.length + i] = newSpenders[i];
        }

        return getApprovalRule(token, allSpenders);
    }
}
