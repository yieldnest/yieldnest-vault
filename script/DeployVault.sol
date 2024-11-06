// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Script.sol";

import {SingleVault} from "src/SingleVault.sol";

contract DeployFactory is Script {
    function run() public {
        vm.startBroadcast();

        new SingleVault();

        vm.stopBroadcast();
    }
}
