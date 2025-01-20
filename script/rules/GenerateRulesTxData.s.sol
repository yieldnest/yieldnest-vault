// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {RulesUtils} from "./RulesUtils.sol";

contract GenerateRulesTxData is RulesUtils, Script {
    function run() external {
        console2.log("\nChain ID:", block.chainid);

        // Replace these with actual addresses
        address vault = MC.YNBNBX;
        address slisBnbStakeManager = MC.SLIS_BNB_STAKE_MANAGER;
        address slisBnb = MC.SLISBNB;
        address asBnbMinter = MC.AS_BNB_MINTER;

        bytes memory slisDepositCalldata = generateSlisDepositRuleCalldata(slisBnbStakeManager);
        bytes memory slisBnbApprovalCalldata;
        {
            address[] memory newSpenders = new address[](1);
            newSpenders[0] = asBnbMinter;
            slisBnbApprovalCalldata = generateApprovalRuleCalldataAppendToExistingSpenders(vault, slisBnb, newSpenders);
        }
        bytes memory astherusMintCalldata = generateAstherusMintRuleCalldata(asBnbMinter);

        address[] memory assets = new address[](3);
        assets[0] = MC.SLISBNB;
        assets[1] = MC.ASBNB;
        assets[2] = MC.WBNB;

        address[] memory receivers = new address[](1);
        receivers[0] = vault;

        bytes memory depositAssetCalldata = generateDepositAssetRuleCalldata(MC.YNASBNBK, assets, receivers);
        bytes memory depositCalldata = generateDepositRuleCalldata(MC.YNASBNBK, vault);

        // Generate approval rules for each asset
        bytes[] memory assetApprovalRulesForYnasbnbk = new bytes[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            address[] memory spenders = new address[](1);
            spenders[0] = MC.YNASBNBK;
            assetApprovalRulesForYnasbnbk[i] = generateApprovalRuleCalldataAppendToExistingSpenders(vault, assets[i], spenders);
        }

        console2.log("\nDeposit Asset Rule Calldata:");
        console2.logBytes(depositAssetCalldata);

        console2.log("\nDeposit Rule Calldata:");
        console2.logBytes(depositCalldata);

        console2.log("\nAsset Approval Rule Calldatas:");
        for (uint256 i = 0; i < assetApprovalRulesForYnasbnbk.length; i++) {
            console2.logBytes(assetApprovalRulesForYnasbnbk[i]);
        }

        console2.log("SLISBNB Deposit Rule Calldata:");
        console2.logBytes(slisDepositCalldata);

        console2.log("\n SLISBNB Approval Rule Calldata:");
        console2.logBytes(slisBnbApprovalCalldata);

        console2.log("\nAsthereus Mint Rule Calldata:");
        console2.logBytes(astherusMintCalldata);

    }
}
