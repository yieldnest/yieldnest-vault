// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeployMockERC20 is Script {
    function run() external {
        string memory name = "Mock slisBNB";
        string memory symbol = "slisBNB";

        vm.startBroadcast();
        new MockERC20(name, symbol);
        vm.stopBroadcast();
    }
}
