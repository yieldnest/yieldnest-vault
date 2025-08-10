// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";

library FxProtocolRules {
    function getFxUSDSavePoolDepositRule(address fxUSDSavePool, address receiver, address[] memory tokenInAllowList)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        // deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        bytes4 funcSig = bytes4(keccak256("deposit(address,address,uint256,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        // receiver param: must be the provided receiver
        address[] memory receiverAllowList = new address[](1);
        receiverAllowList[0] = receiver;
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receiverAllowList});

        // tokenIn param: restrict to provided allowList
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: tokenInAllowList});

        // amountTokenToDeposit param: any uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // minSharesOut param: any uint256
        paramRules[3] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: fxUSDSavePool, funcSig: funcSig, rule: rule});
    }

    function getFxUSDSavePoolRequestRedeemRule(address fxUSDSavePool)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        // requestRedeem(uint256 shares)
        bytes4 funcSig = bytes4(keccak256("requestRedeem(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        // shares param: any uint256
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: fxUSDSavePool, funcSig: funcSig, rule: rule});
    }

    function getFxUSDSavePoolRedeemRule(address fxUSDSavePool, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        // redeem(address receiver, uint256 shares)
        bytes4 funcSig = bytes4(keccak256("redeem(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        // receiver param: must be the provided receiver
        address[] memory receiverAllowList = new address[](1);
        receiverAllowList[0] = receiver;
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receiverAllowList});

        // shares param: any uint256
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: fxUSDSavePool, funcSig: funcSig, rule: rule});
    }
}
