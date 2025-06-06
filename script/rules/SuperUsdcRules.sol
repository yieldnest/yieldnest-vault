// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";

library SuperUsdcRules {
    function getSuperUsdcRedeemRules(address superUsdcVault, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams[] memory)
    {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](1);

        {
            bytes4 funcSig = bytes4(keccak256("redeem(uint256,address,address)"));

            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

            paramRules[0] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

            address[] memory allowList = new address[](1);
            allowList[0] = address(receiver);

            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

            paramRules[2] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

            IVault.FunctionRule memory rule =
                IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

            rules[0] = SafeRules.RuleParams({contractAddress: superUsdcVault, funcSig: funcSig, rule: rule});
        }

        return rules;
    }
}
