// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library BaseRules {
    function getApprovalRule(IVault vault_, address contractAddress, address spender)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        return getApprovalRule(vault_, contractAddress, spender, false);
    }

    function getApprovalRule(IVault vault_, address contractAddress, address spender, bool force)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        return getApprovalRule(vault_, contractAddress, allowList, force);
    }

    function getApprovalRule(IVault vault_, address contractAddress, address[] memory allowList)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        return getApprovalRule(vault_, contractAddress, allowList, false);
    }

    function getApprovalRule(IVault vault_, address contractAddress, address[] memory allowList, bool force)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule, force);
        return (contractAddress, funcSig, rule);
    }

    function getDepositRule(IVault vault_, address contractAddress)
        public
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
        return (contractAddress, funcSig, rule);
    }

    function getDepositAssetRule(IVault vault_, address contractAddress, address asset)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        return getDepositAssetRule(vault_, contractAddress, allowList);
    }

    function getDepositAssetRule(IVault vault_, address contractAddress, address[] memory allowList)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowListReceivers = new address[](1);
        allowListReceivers[0] = address(vault_);

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowListReceivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // vault_.setProcessorRule(contractAddress, funcSig, rule);
        return (contractAddress, funcSig, rule);
    }

    function getWithdrawRule(IVault vault_, address contractAddress)
        public
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
        return (contractAddress, funcSig, rule);
    }

    function getRedeemRule(IVault vault_, address contractAddress)
        public
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("redeem(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
        return (contractAddress, funcSig, rule);
    }

    function getWithdrawAssetRule(IVault vault_, address contractAddress, address asset)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        return getWithdrawAssetRule(vault_, contractAddress, allowList);
    }

    function getWithdrawAssetRule(IVault vault_, address contractAddress, address[] memory assetList)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdrawAsset(address,uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[3] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // vault_.setProcessorRule(contractAddress, funcSig, rule);
        return (contractAddress, funcSig, rule);
    }

    function getWethDepositRule(IVault vault_, address weth_)
        public
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, weth_, funcSig, rule);
        return (weth_, funcSig, rule);
    }

    function getWethWithdrawRule(IVault vault_, address weth_)
        internal
        returns (address, bytes4, IVault.FunctionRule memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        // SafeRules.setProcessorRule(vault_, weth_, funcSig, rule);
        return (weth_, funcSig, rule);
    }
}
