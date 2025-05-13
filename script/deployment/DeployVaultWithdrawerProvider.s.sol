// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";

/*
== Logs ==
  Vault deployed at: 0xD91FE1792069f2bCC092b62F49bFb528244E0402
  Withdrawer deployed at: 0xe4d2585868e9f33Be4A72BC58Afd8c6Bb8209cD7
  Provider deployed at: 0xD5bf05D14be33Eb58506620d3ebe70b80Bf3b01d
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

        // Deploy Withdrawer contract
        Withdrawer withdrawer = new Withdrawer();
        console.log("Withdrawer deployed at:", address(withdrawer));

        // Deploy Provider contract
        Provider provider = new Provider();
        console.log("Provider deployed at:", address(provider));

        // End the broadcast
        vm.stopBroadcast();
    }
}
