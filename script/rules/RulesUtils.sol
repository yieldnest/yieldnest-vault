// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";

contract RulesUtils {
    function _generateRuleCalldata(address contractAddress, bytes4 funcSig, IVault.ParamRule[] memory paramRules)
        public
        pure
        returns (bytes memory)
    {
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return abi.encodeWithSelector(IVault.setProcessorRule.selector, contractAddress, funcSig, rule);
    }

    function generateSlisDepositRuleCalldata(address contractAddress) public pure returns (bytes memory) {
        bytes4 funcSig = bytes4(keccak256("deposit()"));
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);
        return _generateRuleCalldata(contractAddress, funcSig, paramRules);
    }

    function generateAstherusMintRuleCalldata(address contractAddress) public pure returns (bytes memory) {
        bytes4 funcSig = bytes4(keccak256("mintAsBnb(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        return _generateRuleCalldata(contractAddress, funcSig, paramRules);
    }

    function generateApprovalRuleCalldata(address token, address[] memory spenders)
        public
        pure
        returns (bytes memory)
    {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](spenders.length);
        for (uint256 i = 0; i < spenders.length; i++) {
            allowList[i] = spenders[i];
        }

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        return _generateRuleCalldata(token, funcSig, paramRules);
    }

    function generateApprovalRuleCalldataAppendToExistingSpenders(
        address targetVault,
        address token,
        address[] memory newSpenders
    ) public view returns (bytes memory) {
        // Get existing spenders from current rule
        IVault vault = IVault(targetVault);
        IVault.FunctionRule memory rule = vault.getProcessorRule(token, bytes4(keccak256("approve(address,uint256)")));

        // If no existing rule or not active, just use new spenders
        if (!rule.isActive || rule.paramRules.length == 0) {
            return generateApprovalRuleCalldata(token, newSpenders);
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

        return generateApprovalRuleCalldata(token, allSpenders);
    }

    function generateDepositAssetRuleCalldata(
        address contractAddress,
        address[] memory assets,
        address[] memory receivers
    ) public pure returns (bytes memory) {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        address[] memory assetAllowList = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            assetAllowList[i] = assets[i];
        }
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetAllowList});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: receivers});

        return _generateRuleCalldata(contractAddress, funcSig, paramRules);
    }

    function generateDepositRuleCalldata(address contractAddress, address receiver)
        public
        pure
        returns (bytes memory)
    {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;
        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        return _generateRuleCalldata(contractAddress, funcSig, paramRules);
    }
}
