// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";
import {IAugustusV6} from "src/interface/IAugustusV6.sol";

library ParaswapRules {
    function getParaswapRules(address augustus,address paraswapValidator) internal pure returns (SafeRules.RuleParams[] memory) {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](6);
        rules[0] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountIn.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        rules[1] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountInOnBalancerV2.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        rules[2] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountInOnCurveV1.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        rules[3] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountInOnCurveV2.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        rules[4] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountInOnUniswapV2.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        rules[5] = SafeRules.RuleParams({contractAddress: augustus, funcSig: IAugustusV6.swapExactAmountInOnUniswapV3.selector, rule: IVault.FunctionRule({isActive: true, paramRules: new IVault.ParamRule[](0), validator: IValidator(paraswapValidator)})});
        return rules;
    }
}

