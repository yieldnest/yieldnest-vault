// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {RulesUtils} from "./RulesUtils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract GenerateAsBNBRulesTxData is RulesUtils, Script {
    function run() external {
        console2.log("\nChain ID:", block.chainid);

        address vault = MC.YNBNBX;
        address slisBnbStakeManager = MC.SLIS_BNB_STAKE_MANAGER;
        address slisBnb = MC.SLISBNB;
        address asBnbMinter = MC.AS_BNB_MINTER;

        bytes memory slisDepositCalldata = generateSlisDepositRuleCalldata(slisBnbStakeManager);
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
            if (assets[i] == slisBnb) {
                address[] memory spenders = new address[](2);
                spenders[0] = MC.YNASBNBK;
                spenders[1] = asBnbMinter;
                assetApprovalRulesForYnasbnbk[i] =
                    generateApprovalRuleCalldataAppendToExistingSpenders(vault, slisBnb, spenders);
            } else {
                address[] memory spenders = new address[](1);
                spenders[0] = MC.YNASBNBK;
                assetApprovalRulesForYnasbnbk[i] =
                    generateApprovalRuleCalldataAppendToExistingSpenders(vault, assets[i], spenders);
            }
        }

        console2.log("\n=== YNASBNBK depositAsset(address,uint256,address) Rule Calldata ===");
        console2.logBytes(depositAssetCalldata);

        console2.log("\n=== YNASBNBK deposit(uint256,address) Rule Calldata ===");
        console2.logBytes(depositCalldata);

        console2.log("\n=== YNASBNBK approve(address,uint256) Rules for SLISBNB/ASBNB/WBNB ===");
        for (uint256 i = 0; i < assetApprovalRulesForYnasbnbk.length; i++) {
            console2.log("Asset:", assets[i], "Name:", IERC20Metadata(assets[i]).name());
            console2.logBytes(assetApprovalRulesForYnasbnbk[i]);
        }

        console2.log("\n=== SLISBNB Stake Manager deposit() Rule Calldata ===");
        console2.logBytes(slisDepositCalldata);

        console2.log("\n=== ASBNB Minter mintAsBnb(uint256) Rule Calldata ===");
        console2.logBytes(astherusMintCalldata);
    }
}
