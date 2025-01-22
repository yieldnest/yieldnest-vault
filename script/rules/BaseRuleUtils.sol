// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";

contract BaseRuleUtils {
    struct RuleParams {
        address contractAddress;
        bytes4 funcSig;
        IVault.FunctionRule rule;
    }

    function setDepositRule(IVault vault_, address contractAddress) internal {
        setProcessorRule(vault_, getDepositRule(contractAddress, address(vault_)));
    }

    function getDepositRule(address contractAddress, address receiver) internal pure returns (RuleParams memory) {
        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function setDepositAssetRule(IVault vault_, address contractAddress, address asset) internal {
        setProcessorRule(vault_, getDepositAssetRule(contractAddress, asset, address(vault_)));
    }

    function getDepositAssetRule(address contractAddress, address asset, address receiver)
        internal
        pure
        returns (RuleParams memory)
    {
        address[] memory assetList = new address[](1);
        assetList[0] = asset;

        address[] memory receivers = new address[](1);
        receivers[0] = address(receiver);

        return getDepositAssetRule(contractAddress, assetList, receivers);
    }

    function setDepositAssetRule(IVault vault_, address contractAddress, address[] memory assetList) internal {
        address[] memory receivers = new address[](1);
        receivers[0] = address(vault_);

        setProcessorRule(vault_, getDepositAssetRule(contractAddress, assetList, receivers));
    }

    function getDepositAssetRule(address contractAddress, address[] memory assetList, address[] memory receivers)
        internal
        pure
        returns (RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function setWithdrawRule(IVault vault_, address contractAddress) internal {
        setProcessorRule(vault_, getWithdrawRule(contractAddress, address(vault_)));
    }

    function getWithdrawRule(address contractAddress, address receiver) internal pure returns (RuleParams memory) {
        address[] memory receivers = new address[](1);
        receivers[0] = address(receiver);

        return getWithdrawRule(contractAddress, receivers);
    }

    function getWithdrawRule(address contractAddress, address[] memory receivers)
        internal
        pure
        returns (RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function setWithdrawAssetRule(IVault vault_, address contractAddress, address asset) internal {
        setProcessorRule(vault_, getWithdrawAssetRule(contractAddress, asset, address(vault_)));
    }

    function getWithdrawAssetRule(address contractAddress, address asset, address receiver)
        internal
        pure
        returns (RuleParams memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        address[] memory receivers = new address[](1);
        receivers[0] = address(receiver);

        return getWithdrawAssetRule(contractAddress, allowList, receivers);
    }

    function setWithdrawAssetRule(IVault vault_, address contractAddress, address[] memory assetList) internal {
        address[] memory receivers = new address[](1);
        receivers[0] = address(vault_);

        setProcessorRule(vault_, getWithdrawAssetRule(contractAddress, assetList, receivers));
    }

    function getWithdrawAssetRule(address contractAddress, address[] memory assetList, address[] memory receivers)
        internal
        pure
        returns (RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdrawAsset(address,uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        paramRules[3] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function setApprovalRule(IVault vault_, address contractAddress, address spender) internal {
        setProcessorRule(vault_, getApprovalRule(contractAddress, spender));
    }

    function getApprovalRule(address contractAddress, address spender) internal pure returns (RuleParams memory) {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        return getApprovalRule(contractAddress, allowList);
    }

    function setApprovalRule(IVault vault_, address contractAddress, address[] memory allowList) internal {
        setProcessorRule(vault_, getApprovalRule(contractAddress, allowList));
    }

    function getApprovalRule(address contractAddress, address[] memory allowList)
        internal
        pure
        returns (RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function setWethDepositRule(IVault vault_, address weth_) internal {
        setProcessorRule(vault_, getWethDepositRule(weth_));
    }

    function getWethDepositRule(address weth_) internal pure returns (RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: weth_, funcSig: funcSig, rule: rule});
    }

    function setWethWithdrawRule(IVault vault_, address weth_) internal {
        setProcessorRule(vault_, getWethWithdrawRule(weth_));
    }

    function getWethWithdrawRule(address weth_) internal pure returns (RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return RuleParams({contractAddress: weth_, funcSig: funcSig, rule: rule});
    }

    function setProcessorRule(IVault vault_, RuleParams memory rule) internal {
        vault_.setProcessorRule(rule.contractAddress, rule.funcSig, rule.rule);
    }

    function setProcessorRules(IVault vault_, RuleParams[] memory rules_) internal {
        address[] memory contractsAddresses = new address[](rules_.length);
        bytes4[] memory funcSigs = new bytes4[](rules_.length);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](rules_.length);

        for (uint256 i = 0; i < rules_.length; i++) {
            contractsAddresses[i] = rules_[i].contractAddress;
            funcSigs[i] = rules_[i].funcSig;
            rules[i] = rules_[i].rule;
        }

        vault_.setProcessorRules(contractsAddresses, funcSigs, rules);
    }

    function _generateCalldata(RuleParams[] memory rules_) public pure returns (bytes memory) {
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

    function _generateCalldata(RuleParams memory ruleParams) public pure returns (bytes memory) {
        return _generateCalldata(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
    }

    function _generateCalldata(address contractAddress, bytes4 funcSig, IVault.FunctionRule memory rule)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IVault.setProcessorRule.selector, contractAddress, funcSig, rule);
    }
}
