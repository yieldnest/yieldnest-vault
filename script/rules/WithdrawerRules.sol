// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library WithdrawerRules {
    function getRequestWithdrawRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("requestWithdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getClaimWithdrawRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("claimWithdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }
}
