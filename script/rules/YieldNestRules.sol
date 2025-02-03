// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library YieldNestRules {
    function setYnETHDepositRule(IVault vault_, address contractAddress, address receiver) public {
        bytes4 funcSig = bytes4(keccak256("depositETH(address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function setYnEigenDepositRule(IVault vault_, address contractAddress, address[] memory assetList, address receiver)
        public
    {
        bytes4 funcSig = bytes4(keccak256("deposit(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }
}
