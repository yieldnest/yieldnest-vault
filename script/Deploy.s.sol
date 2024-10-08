// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Script.sol";

import {VaultFactory} from "src/VaultFactory.sol";
import {IVaultFactory} from "src/IVaultFactory.sol";
import {AnvilActors, HoleskyActors, ChapelActors, BscActors, IActors} from "script/Actors.sol";
import {SingleVault} from "src/SingleVault.sol";
import {TransparentUpgradeableProxy, TimelockController} from "src/Common.sol";

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

        if (block.chainid == 56) {
            vm.startBroadcast();
            BscActors actors = new BscActors();
            uint256 minDelay = 86400; // 24 hours in seconds
            deployVaultFactory(actors, minDelay);
        }
    }

    function deployVaultFactory(IActors actors, uint256 minDelay) public returns (address) {
        address vaultFactoryImpl = address(new VaultFactory());
        address singleVaultImpl = address(new SingleVault());

        address[] memory proposers = new address[](2);
        proposers[0] = actors.PROPOSER_1();
        proposers[1] = actors.PROPOSER_2();

        address[] memory executors = new address[](2);
        executors[0] = actors.EXECUTOR_1();
        executors[1] = actors.EXECUTOR_2();

        address admin = actors.ADMIN();

        string memory funcSig = "initialize(address,address,address)";

        TimelockController timelock = new TimelockController(minDelay, proposers, executors, admin);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            vaultFactoryImpl,
            address(timelock),
            abi.encodeWithSignature(funcSig, singleVaultImpl, admin, address(timelock))
        );
        return address(proxy);
    }
}
