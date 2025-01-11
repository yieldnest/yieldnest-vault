// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {Script} from "lib/forge-std/src/Script.sol";

import {Vault} from "src/Vault.sol";

contract DeployVault is Script {
    function run() public virtual {
        vm.startBroadcast();

        address vault = address(new Vault());

        vm.stopBroadcast();

        // Store vault implementation in JSON file
        string memory json = string.concat("{\"Vault\": \"", vm.toString(vault), "\"}");
        vm.writeFile(string.concat("deployments/vault-", vm.toString(block.chainid), ".json"), json);
    }
}
