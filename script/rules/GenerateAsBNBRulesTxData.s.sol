// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {RuleUtils} from "./RuleUtils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract GenerateAsBNBRulesTxData is RuleUtils, Script {
    function run() external view {
        console2.log("\nChain ID:", block.chainid);

        address vault = MC.YNBNBX;
        address slisBnbStakeManager = MC.SLIS_BNB_STAKE_MANAGER;
        address slisBnb = MC.SLISBNB;
        address asBnbMinter = MC.AS_BNB_MINTER;

        address[] memory assets = new address[](3);
        assets[0] = MC.SLISBNB;
        assets[1] = MC.ASBNB;
        assets[2] = MC.WBNB;

        address[] memory receivers = new address[](1);
        receivers[0] = vault;

        RuleParams[] memory rules = new RuleParams[](assets.length + 4); // 4 more rules follow the asset approval rules

        // Generate approval rules for each asset
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == slisBnb) {
                address[] memory spenders = new address[](2);
                spenders[0] = MC.YNASBNBK;
                spenders[1] = asBnbMinter;
                rules[i] = getApprovalRuleAppendToExistingSpenders(vault, slisBnb, spenders);
            } else {
                address[] memory spenders = new address[](1);
                spenders[0] = MC.YNASBNBK;
                rules[i] = getApprovalRuleAppendToExistingSpenders(vault, assets[i], spenders);
            }
        }
        console2.log("\n=== Added YNASBNBK approve(address,uint256) Rules for SLISBNB/ASBNB/WBNB ===");

        RuleParams memory depositAssetCalldata = getDepositAssetRule(MC.YNASBNBK, assets, receivers);
        console2.log("\n=== Added YNASBNBK depositAsset(address,uint256,address) Rule ===");

        RuleParams memory depositCalldata = getDepositRule(MC.YNASBNBK, vault);
        console2.log("\n=== Added YNASBNBK deposit(uint256,address) Rule ===");

        RuleParams memory slisDepositCalldata = getSlisDepositRule(slisBnbStakeManager);
        console2.log("\n=== Added SLISBNB Stake Manager deposit() Rule ===");

        RuleParams memory astherusMintCalldata = getAstherusMintRule(asBnbMinter);
        console2.log("\n=== Added ASBNB Minter mintAsBnb(uint256) Rule ===");

        rules[assets.length] = depositAssetCalldata;
        rules[assets.length + 1] = depositCalldata;
        rules[assets.length + 2] = slisDepositCalldata;
        rules[assets.length + 3] = astherusMintCalldata;

        bytes memory rulesCalldata = _generateCalldata(rules);

        console2.log("\n=== Final Set Processor Rules Calldata ===");
        console2.logBytes(rulesCalldata);
    }
}
