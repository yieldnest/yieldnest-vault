// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library StakedEtherRules {
    function setWrapRule(IVault vault_, address wsteth_) public {
        bytes4 funcSig = bytes4(keccak256("wrap(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, wsteth_, funcSig, rule);
    }

    function setUnwrapRule(IVault vault_, address wsteth_) public {
        bytes4 funcSig = bytes4(keccak256("unwrap(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, wsteth_, funcSig, rule);
    }
}
