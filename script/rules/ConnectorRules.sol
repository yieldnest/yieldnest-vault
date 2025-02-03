// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

library ConnectorRules {
    function setConnectorDepositRule(IVault vault_, address connectorAddress) internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,uint256,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, connectorAddress, funcSig, rule);
    }

    function processConnectorDeposit(
        IVault vault_,
        address connectorAddress,
        address assetA,
        address assetB,
        uint256 amountA,
        uint256 amountB,
        uint256 minOut
    ) internal returns (uint256 shares) {
        address[] memory targets = new address[](3);
        targets[0] = assetA;
        targets[1] = assetB;
        targets[2] = connectorAddress;

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amountA);
        data[1] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amountB);
        data[2] = abi.encodeWithSignature("deposit(uint256,uint256,uint256)", amountA, amountB, minOut);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        shares = abi.decode(returnData[2], (uint256));
    }

    function setConnectorWithdrawRule(IVault vault_, address connectorAddress) internal {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,uint256,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        SafeRules.setProcessorRule(vault_, connectorAddress, funcSig, rule);
    }

    function processConnectorWithdraw(
        IVault vault_,
        address connectorAddress,
        address strategyAddress,
        uint256 amount,
        uint256 minAmountA,
        uint256 minAmountB
    ) internal returns (uint256[2] memory) {
        address[] memory targets = new address[](2);
        targets[0] = strategyAddress;
        targets[1] = connectorAddress;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", connectorAddress, amount);
        data[1] = abi.encodeWithSignature("withdraw(uint256,uint256,uint256)", amount, minAmountA, minAmountB);

        bytes[] memory returnData = vault_.processor(targets, values, data);

        return abi.decode(returnData[1], (uint256[2]));
    }
}
