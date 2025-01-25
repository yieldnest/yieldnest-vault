// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";

contract WithdrawerUtils {
    function setRequestWithdrawRule(IVault vault_, address contractAddress) internal {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("requestWithdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function processRequestWithdraw(IVault vault_, address contractAddress, address asset_, uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = contractAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", contractAddress, amount);
        data[1] = abi.encodeWithSignature("requestWithdraw(uint256)", amount);

        vault_.processor(targets, values, data);
    }

    function setClaimWithdrawRule(IVault vault_, address contractAddress) internal {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("claimWithdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function processClaimWithdraw(IVault vault_, address contractAddress, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdraw(uint256)", tokenId);

        vault_.processor(targets, values, data);
    }

    function setApprovalRule(IVault vault_, address contractAddress, address spender) internal {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        setApprovalRule(vault_, contractAddress, allowList);
    }

    function setApprovalRule(IVault vault_, address contractAddress, address[] memory allowList) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }
}
