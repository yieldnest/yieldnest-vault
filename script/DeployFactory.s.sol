// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Script.sol";

import {VaultFactory} from "src/VaultFactory.sol";
import {IActors, MainnetActors, HoleskyActors} from "script/Actors.sol";
import {MainnetContracts, HoleskyContracts} from "script/Contracts.sol";
import {SingleVault} from "src/SingleVault.sol";
import {TransparentUpgradeableProxy, TimelockController} from "src/Common.sol";

contract DeployFactory is Script {
    function run() public {
        if (block.chainid == 17000) {
            vm.startBroadcast();
            HoleskyActors actors = new HoleskyActors();
            uint256 minDelay = 10; // seconds
            address weth = HoleskyContracts.WETH;
            deployVaultFactory(actors, minDelay, weth);
        }

        if (block.chainid == 1 || block.chainid == 31337) {
            vm.startBroadcast();
            MainnetActors actors = new MainnetActors();
            uint256 minDelay = 86400; // seconds
            address weth = MainnetContracts.WETH;
            deployVaultFactory(actors, minDelay, weth);
        }
    }

    function deployVaultFactory(IActors actors, uint256 minDelay, address weth) public returns (address) {
        address vaultFactoryImpl = address(new VaultFactory());
        address singleVaultImpl = address(new SingleVault());

        address[] memory proposers = new address[](1);
        proposers[0] = actors.PROPOSER_1();

        address[] memory executors = new address[](1);
        executors[0] = actors.EXECUTOR_1();

        address admin = actors.ADMIN();

        string memory funcSig = "initialize(address,address,address,address)";

        TimelockController timelock = new TimelockController(minDelay, proposers, executors, admin);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            vaultFactoryImpl,
            address(timelock),
            abi.encodeWithSignature(funcSig, singleVaultImpl, admin, address(timelock), weth)
        );
        return address(proxy);
    }
}
