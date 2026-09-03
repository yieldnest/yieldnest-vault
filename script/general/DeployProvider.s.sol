// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";

import {Provider} from "src/module/Provider.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

contract DeployProvider is Script {
    function run() public virtual {
        vm.startBroadcast();

        address provider = address(new Provider(MC.WUSDC, MC.FLEX_STRATEGY_USDC));

        vm.stopBroadcast();

        // Store provider implementation in JSON file
        string memory json = string.concat("{\"Provider\": \"", vm.toString(provider), "\"}");
        vm.writeFile(string.concat("deployments/provider-", vm.toString(block.chainid), ".json"), json);
    }
}
