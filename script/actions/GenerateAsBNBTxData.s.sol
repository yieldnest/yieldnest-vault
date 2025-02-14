// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IStakeManager} from "lib/synclub-contracts/contracts/interfaces/IStakeManager.sol";
import {IAsBnbMinter} from "src/interface/external/astherus/IAsBnbMinter.sol";

contract GenerateAsBNBTxData is Script {
    function run() external {
        console2.log("=== Generate Processor Transaction Data ===");
        console2.log("Current Block Number: %s", block.number);
        console2.log("Current Chain ID: %s", block.chainid);

        uint256 bnbAmount = 1728 ether;

        // Generate calldata for WBNB withdraw
        bytes memory wbnbWithdrawData = abi.encodeWithSelector(bytes4(keccak256("withdraw(uint256)")), bnbAmount);

        console2.log("=== WBNB Withdraw Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.WBNB));
        console2.log("Amount: %s", bnbAmount);
        console2.log("Transaction data:");
        console2.logBytes(wbnbWithdrawData);

        // Generate calldata for SLISBNB deposit
        bytes memory slisDepositData = abi.encodeWithSelector(bytes4(keccak256("deposit()")));
        // Get expected slisBNB amount based on current rate
        uint256 slisAmount = IStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertBnbToSnBnb(bnbAmount);

        console2.log("\n=== SLISBNB Deposit Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.SLIS_BNB_STAKE_MANAGER));
        console2.log("BNB Amount: 950 ether");
        console2.log("Expected slisBNB Amount: %s", slisAmount);
        console2.log("Receiver: %s", vm.toString(MC.YNBNBX));
        console2.log("Value: %s", bnbAmount);
        console2.log("Transaction data:");
        console2.logBytes(slisDepositData);

        // Generate calldata for SLISBNB approve to ASBNB minter
        bytes memory slisApproveData = abi.encodeWithSelector(ERC20.approve.selector, MC.AS_BNB_MINTER, slisAmount);

        console2.log("\n=== SLISBNB Approve Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.SLISBNB));
        console2.log("Spender: %s", vm.toString(MC.AS_BNB_MINTER));
        console2.log("Amount: %s", slisAmount);
        console2.log("Transaction data:");
        console2.logBytes(slisApproveData);

        // Generate calldata for ASBNB mint
        bytes memory asBnbMintData = abi.encodeWithSelector(bytes4(keccak256("mintAsBnb(uint256)")), slisAmount);

        console2.log("\n=== ASBNB Mint Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.AS_BNB_MINTER));
        console2.log("Amount: %s", slisAmount);
        console2.log("Transaction data:");
        console2.logBytes(asBnbMintData);

        // Get expected asBNB amount based on current rate
        uint256 asBnbAmount = IAsBnbMinter(MC.AS_BNB_MINTER).convertToAsBnb(slisAmount);

        console2.log("\n=== ASBNB Conversion Details ===");
        console2.log("SLISBNB Amount: %s", slisAmount);
        console2.log("Expected ASBNB Amount: %s", asBnbAmount);

        // Generate calldata for ASBNB approve to ynAsBNBk
        bytes memory asBnbApproveData = abi.encodeWithSelector(ERC20.approve.selector, MC.YNASBNBK, asBnbAmount);

        console2.log("\n=== ASBNB Approve Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.ASBNB));
        console2.log("Spender: %s", vm.toString(MC.YNASBNBK));
        console2.log("Amount: %s", asBnbAmount);
        console2.log("Transaction data:");
        console2.logBytes(asBnbApproveData);

        // Generate calldata for ynAsBNBk depositAsset
        bytes memory depositAssetData = abi.encodeWithSelector(
            bytes4(keccak256("depositAsset(address,uint256,address)")), MC.ASBNB, asBnbAmount, MC.YNBNBX
        );

        console2.log("\n=== YNASBNBK DepositAsset Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.YNASBNBK));
        console2.log("Asset: %s", vm.toString(MC.ASBNB));
        console2.log("Amount: %s", asBnbAmount);
        console2.log("Receiver: %s", vm.toString(MC.YNBNBX));
        console2.log("Transaction data:");
        console2.logBytes(depositAssetData);

        // Generate processor tx data to execute all transactions
        address[] memory targets = new address[](6);
        uint256[] memory values = new uint256[](6);
        bytes[] memory data = new bytes[](6);

        // 1. Withdraw WBNB
        targets[0] = MC.WBNB;
        values[0] = 0;
        data[0] = wbnbWithdrawData;

        // 2. Mint SLISBNB
        targets[1] = MC.SLIS_BNB_STAKE_MANAGER;
        values[1] = bnbAmount;
        data[1] = slisDepositData;

        // 3. Approve SLISBNB for asBNB minting
        targets[2] = MC.SLISBNB;
        values[2] = 0;
        data[2] = slisApproveData;

        // 4. Mint asBNB
        targets[3] = MC.AS_BNB_MINTER;
        values[3] = 0;
        data[3] = asBnbMintData;

        // 5. Approve asBNB to ynAsBNBk
        targets[4] = MC.ASBNB;
        values[4] = 0;
        data[4] = asBnbApproveData;

        // 6. Deposit asBNB to ynAsBNBk
        targets[5] = MC.YNASBNBK;
        values[5] = 0;
        data[5] = depositAssetData;

        bytes memory processorData =
            abi.encodeWithSelector(bytes4(keccak256("processor(address[],uint256[],bytes[])")), targets, values, data);

        console2.log("\n=== Processor Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.YNBNBX));
        console2.log("Transaction data:");
        console2.logBytes(processorData);
    }
}
