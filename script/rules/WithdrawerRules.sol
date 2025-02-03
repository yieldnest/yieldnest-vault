// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library WithdrawerRules {
    function setRequestWithdrawalRule(IVault vault_, address contractAddress) internal {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("requestWithdrawal(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function processRequestWithdrawal(IVault vault_, address contractAddress, address asset_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = contractAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", contractAddress, amount);
        data[1] = abi.encodeWithSignature("requestWithdrawal(uint256)", amount);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        tokenId = abi.decode(returnData[1], (uint256));
    }

    function setClaimWithdrawalRule(IVault vault_, address contractAddress) internal {
        bytes4 funcSig = bytes4(keccak256("claimWithdrawal(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowListReceivers = new address[](1);
        allowListReceivers[0] = address(vault_);

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowListReceivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function processClaimWithdrawal(IVault vault_, address contractAddress, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdrawal(uint256,address)", tokenId, address(vault_));

        vault_.processor(targets, values, data);
    }

    function setRequestWithdrawalWstETHRule(IVault vault_, address contractAddress) internal {
        bytes4 funcSig = bytes4(keccak256("requestWithdrawalsWstETH(uint256[],address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowListReceivers = new address[](1);
        allowListReceivers[0] = address(vault_);

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowListReceivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function processRequestWithdrawalWstETH(IVault vault_, address contractAddress, address asset_, uint256 amount)
        internal
        returns (uint256 tokenId)
    {
        address[] memory targets = new address[](2);
        targets[0] = asset_;
        targets[1] = contractAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", contractAddress, amount);
        data[1] = abi.encodeWithSignature("requestWithdrawalsWstETH(uint256[],address)", amounts, address(vault_));

        bytes[] memory returnData = vault_.processor(targets, values, data);

        uint256[] memory tokenIds = abi.decode(returnData[1], (uint256[]));
        tokenId = tokenIds[0];
    }

    function setClaimWithdrawalWstETHRule(IVault vault_, address contractAddress) internal {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("claimWithdrawal(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function processClaimWithdrawalWstETH(IVault vault_, address contractAddress, uint256 tokenId) internal {
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("claimWithdrawal(uint256)", tokenId);

        vault_.processor(targets, values, data);
    }
}
