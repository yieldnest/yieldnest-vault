// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Script.sol";

import {VaultFactory} from "src/VaultFactory.sol";
import {AnvilActors, HoleskyActors, ChapelActors, IActors} from "script/Actors.sol";
import {SingleVault} from "src/SingleVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";


contract DeployVaultFactory is Script {
    function run() public {
        if (block.chainid == 31337) {
            vm.startBroadcast();
            AnvilActors actors = new AnvilActors();
            uint256 minDelay = 10; // seconds
            deployVaultFactory(actors, minDelay);
        }

        if (block.chainid == 17000) {
            vm.startBroadcast();
            HoleskyActors actors = new HoleskyActors();
            uint256 minDelay = 10; // seconds
            deployVaultFactory(actors, minDelay);
        }

        if (block.chainid == 97) {
            vm.startBroadcast();
            ChapelActors actors = new ChapelActors();
            uint256 minDelay = 10; // seconds
            deployVaultFactory(actors, minDelay);
        }
    }

    function deployVaultFactory(IActors actors, uint256 minDelay) internal {
        address singleVaultImpl = address(new SingleVault());

        address[] memory proposers = new address[](2);
        proposers[0] = actors.PROPOSER_1();
        proposers[1] = actors.PROPOSER_2();

        address[] memory executors = new address[](2);
        executors[0] = actors.EXECUTOR_1();
        executors[1] = actors.EXECUTOR_2();

        address admin = actors.ADMIN();

        new VaultFactory(singleVaultImpl, proposers, executors, minDelay, admin);
    }
}
