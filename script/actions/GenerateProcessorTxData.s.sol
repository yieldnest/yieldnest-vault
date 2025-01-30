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
import {MainnetActors} from "script/Actors.sol";


contract GenerateProcessorTxData is Script {


    function run() external {
        uint256 DEPOSIT_AMOUNT = 118 ether;

        MainnetActors    actors = new MainnetActors();

        console2.log("Target Multisig: %s", vm.toString(actors.PROCESSOR()));

        console2.log("Target Vault: %s", vm.toString(MC.YNBNBX));

        console2.log("=== Generate Processor Transaction Data ===");
        console2.log("Current Block Number: %s", block.number);
        console2.log("Current Chain ID: %s", block.chainid);

        // Generate calldata for approve(address,uint256)
        bytes memory txData = abi.encodeWithSelector(
            ERC20.approve.selector,
            MC.BUFFER,
            DEPOSIT_AMOUNT
        );

        console2.log("=== Transaction Details ===");
        console2.log("Target: %s", vm.toString(MC.WBNB));
        console2.log("Spender: %s", vm.toString(MC.BUFFER));
        console2.log("Approval Amount: %s", DEPOSIT_AMOUNT);
        console2.log("Transaction data:");
        console2.logBytes(txData);

        // Generate calldata for deposit(uint256,address)
        bytes memory depositData = abi.encodeWithSelector(
            ERC4626.deposit.selector,
            DEPOSIT_AMOUNT,
            MC.YNBNBX
        );

        console2.log("\n=== Deposit Transaction Details ===");
        console2.log("Target Buffer: %s", vm.toString(MC.BUFFER));
        console2.log("Deposit Amount: %s", DEPOSIT_AMOUNT);
        console2.log("Receiver: %s", vm.toString(MC.YNBNBX));
        console2.log("Transaction data:");
        console2.logBytes(depositData);
    }
}