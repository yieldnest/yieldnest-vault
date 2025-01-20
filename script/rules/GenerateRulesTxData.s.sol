// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";

contract GenerateRulesTxData is Script {
    function _generateRuleCalldata(address contractAddress, bytes4 funcSig, IVault.ParamRule[] memory paramRules)
        internal
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

    function generateApprovalRuleCalldata(address token, address spender) public pure returns (bytes memory) {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        return _generateRuleCalldata(token, funcSig, paramRules);
    }

    function generateDepositAssetRuleCalldata(address contractAddress) public pure returns (bytes memory) {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);
        paramRules[0] = 
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: new address[](0)});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: new address[](0)});

        return _generateRuleCalldata(contractAddress, funcSig, paramRules);
    }

    function run() external {
        // Replace these with actual addresses
        address vault = address(0);
        address slisBnbStakeManager = address(0);
        address slisBnb = address(0);
        address asBnbMinter = address(0);

        bytes memory slisDepositCalldata = generateSlisDepositRuleCalldata(slisBnbStakeManager);
        bytes memory approvalCalldata = generateApprovalRuleCalldata(slisBnb, asBnbMinter);
        bytes memory astherusMintCalldata = generateAstherusMintRuleCalldata(asBnbMinter);

        console2.log("SLIS Deposit Rule Calldata:");
        console2.logBytes(slisDepositCalldata);

        console2.log("\nApproval Rule Calldata:");
        console2.logBytes(approvalCalldata);

        console2.log("\nAsthereus Mint Rule Calldata:");
        console2.logBytes(astherusMintCalldata);
    }
}
