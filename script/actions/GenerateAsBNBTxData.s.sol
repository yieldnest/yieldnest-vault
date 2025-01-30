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

        uint256 bnbAmount = 950 ether;

        
        // Generate calldata for WBNB withdraw
        bytes memory wbnbWithdrawData = abi.encodeWithSelector(
            bytes4(keccak256("withdraw(uint256)")),
            bnbAmount
        );

        console2.log("=== WBNB Withdraw Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.WBNB));
        console2.log("Amount: %s", bnbAmount);
        console2.log("Transaction data:");
        console2.logBytes(wbnbWithdrawData);

        // Generate calldata for SLISBNB deposit
        bytes memory slisDepositData = abi.encodeWithSelector(
            bytes4(keccak256("deposit()"))
        );
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
        bytes memory slisApproveData = abi.encodeWithSelector(
            ERC20.approve.selector,
            MC.AS_BNB_MINTER,
            slisAmount 
        );

        console2.log("\n=== SLISBNB Approve Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.SLISBNB));
        console2.log("Spender: %s", vm.toString(MC.AS_BNB_MINTER));
        console2.log("Amount: %s", slisAmount);
        console2.log("Transaction data:");
        console2.logBytes(slisApproveData);

        // Generate calldata for ASBNB mint
        bytes memory asBnbMintData = abi.encodeWithSelector(
            bytes4(keccak256("mintAsBnb(uint256)")),
            slisAmount
        );

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

        asBnbAmount = 915142343727850655700;

        // Generate calldata for ASBNB approve to ynAsBNBk
        bytes memory asBnbApproveData = abi.encodeWithSelector(
            ERC20.approve.selector,
            MC.YNASBNBK,
            asBnbAmount
        );

        console2.log("\n=== ASBNB Approve Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.ASBNB));
        console2.log("Spender: %s", vm.toString(MC.YNASBNBK)); 
        console2.log("Amount: %s", asBnbAmount);
        console2.log("Transaction data:");
        console2.logBytes(asBnbApproveData);


        // Generate calldata for ynAsBNBk depositAsset
        bytes memory depositAssetData = abi.encodeWithSelector(
            bytes4(keccak256("depositAsset(address,uint256,address)")),
            MC.ASBNB,
            asBnbAmount,
            MC.YNBNBX
        );

        console2.log("\n=== YNASBNBK DepositAsset Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.YNASBNBK));
        console2.log("Asset: %s", vm.toString(MC.ASBNB));
        console2.log("Amount: %s", asBnbAmount);
        console2.log("Receiver: %s", vm.toString(MC.YNBNBX));
        console2.log("Transaction data:");
        console2.logBytes(depositAssetData);


    }
}