// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";

/*
== Logs ==
  Vault deployed at: 0xCE11f544B4291504f0c8cB66C0f6c0409C0f4978
  Provider deployed at: 0x2338380AB6d5EeC6964403E7241bf1AD0E9A1499
*/

/**
 * @title DeployVaultWithdrawerProvider
 * @notice Script to deploy Provider contract
 */
contract DeployVaultWithdrawerProvider is Script {
    function run() external {
        // Start the broadcast to record and send transactions
        vm.startBroadcast();

        // Deploy Vault contract
        Vault vault = new Vault();
        console.log("Vault deployed at:", address(vault));

        // Deploy Provider contract
        Provider provider = new Provider();
        console.log("Provider deployed at:", address(provider));

        // End the broadcast
        vm.stopBroadcast();
    }
}
