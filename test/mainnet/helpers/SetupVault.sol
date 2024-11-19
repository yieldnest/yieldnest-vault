// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy as TUProxy, TimelockController as TLC} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts} from "script/Contracts.sol";

contract SetupVault is Test, Etches, MainnetActors {

    function setup() public {
        
        Vault vaultImplementation = new Vault();

        TLC timelock = TLC(MainnetContracts.TIMELOCK);
    }
}