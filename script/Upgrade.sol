    // SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Script.sol";

import {VaultFactory} from "src/VaultFactory.sol";
import {IActors, MainnetActors, HoleskyActors} from "script/Actors.sol";
import {MainnetContracts, HoleskyContracts} from "script/Contracts.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract UpgradeVault is Script {
    address public constant NEW_VAULT_IMPLEMENTATION = 0x9974391FE4196fBEa310d3fE01A3d2b8299266e5; // change me

    address TIMELOCK;
    address PROXY;
    address ADMIN;
    address PROPOSER_1;
    address EXECUTOR_1;
    address NEW_VAULT;
    address PROXY_ADMIN;
    uint256 DELAY;

    // Define events
    event MultiSig(address safe);

    event Timelock(address timelock);

    event TimelockScheduled(
        address indexed target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay
    );

    event TimelockIdGenerated(bytes32 id);

    constructor() {
        if (block.chainid == 1) {
            // Mainnet
            MainnetActors actors = new MainnetActors();
            ADMIN = actors.ADMIN();
            PROPOSER_1 = actors.PROPOSER_1();
            EXECUTOR_1 = actors.EXECUTOR_1();
            PROXY = MainnetContracts.YNETHX;
            PROXY_ADMIN = MainnetContracts.PROXY_ADMIN;
            TIMELOCK = MainnetContracts.TIMELOCK;
            DELAY = 84600;
        } else if (block.chainid == 17000) {
            // Holesky
            HoleskyActors actors = new HoleskyActors();
            ADMIN = actors.ADMIN();
            PROPOSER_1 = actors.PROPOSER_1();
            EXECUTOR_1 = actors.EXECUTOR_1();
            PROXY = HoleskyContracts.YNETHX;
            PROXY_ADMIN = HoleskyContracts.PROXY_ADMIN;
            TIMELOCK = HoleskyContracts.TIMELOCK;
            DELAY = 10;
        } else {
            revert("Unsupported chainId");
        }
    }

    function run() public {
        // the traget is the proxy admin
        address target = PROXY_ADMIN;
        uint256 value = 0;

        emit MultiSig(ADMIN);

        emit Timelock(TIMELOCK);

        string memory selector = "upgradeAndCall(address,address,bytes)";

        bytes memory data = abi.encodeWithSignature(selector, PROXY, NEW_VAULT_IMPLEMENTATION, "");

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        // Emit the event to log the scheduling details
        emit TimelockScheduled(target, value, data, predecessor, salt, DELAY);

        // Calculate the id and emit it
        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        emit TimelockIdGenerated(id);
    }
}
