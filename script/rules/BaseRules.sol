// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library BaseRules {
    function getApprovalRule(address contractAddress, address spender)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        return getApprovalRule(contractAddress, allowList);
    }

    function getApprovalRule(address contractAddress, address[] memory allowList)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getDepositRule(address contractAddress, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getDepositAssetRule(address contractAddress, address asset, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        return getDepositAssetRule(contractAddress, allowList, receiver);
    }

    function getDepositAssetRule(address contractAddress, address[] memory allowList, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowListReceivers = new address[](1);
        allowListReceivers[0] = address(receiver);

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowListReceivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getWithdrawRule(address contractAddress, address receiver)
        public
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getRedeemRule(address contractAddress, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("redeem(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getWithdrawAssetRule(address contractAddress, address asset, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        return getWithdrawAssetRule(contractAddress, allowList, receiver);
    }

    function getWithdrawAssetRule(address contractAddress, address[] memory assetList, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdrawAsset(address,uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(receiver);

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[3] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getWethDepositRule(address weth_) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: weth_, funcSig: funcSig, rule: rule});
    }

    function getWethWithdrawRule(address weth_) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: weth_, funcSig: funcSig, rule: rule});
    }

    function getTransferRule(address token, address recipient) internal pure returns (SafeRules.RuleParams memory) {
        address[] memory allowList = new address[](1);
        allowList[0] = recipient;

        return getTransferRule(token, allowList);
    }

    function getTransferRule(address token, address[] memory allowList)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("transfer(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: token, funcSig: funcSig, rule: rule});
    }

    /**
     * @notice Get an approval rule for an asset with a spender appended to the *Existing* allowlist
     * @param asset The asset to approve
     * @param spender The spender to append to the allowlist
     * @param vault The vault to get the current rule from
     * @return SafeRules.RuleParams The approval rule with the spender appended to the allowlist
     */
    function getAppendApprovalRule(address asset, address spender, IVault vault)
        internal
        view
        returns (SafeRules.RuleParams memory)
    {
        // Get the current rule for the asset's approve function
        bytes4 approveSelector = bytes4(keccak256("approve(address,uint256)"));
        IVault.FunctionRule memory currentRule = vault.getProcessorRule(asset, approveSelector);

        // Create a whitelist array to store the existing addresses plus the new spender
        address[] memory whitelist;

        if (currentRule.isActive) {
            // Get the current whitelist from the rule
            address[] memory currentWhitelist = currentRule.paramRules[0].allowList;
            // Initialize the new whitelist with size + 1
            whitelist = new address[](currentWhitelist.length + 1);

            for (uint256 i = 0; i < currentWhitelist.length; i++) {
                whitelist[i] = currentWhitelist[i];
            }

            // Add the new spender address
            whitelist[currentWhitelist.length] = spender;
        } else {
            // Create a new whitelist with the spender address
            whitelist = new address[](1);
            whitelist[0] = spender;
        }

        // Create a new approve rule with the spender added to the allowlist
        SafeRules.RuleParams memory approveRule = BaseRules.getApprovalRule(asset, whitelist);

        return approveRule;
    }
}
