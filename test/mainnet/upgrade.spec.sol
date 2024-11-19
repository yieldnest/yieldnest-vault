// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultMainnetUpgradeTest is Test, MainnetActors {

    Vault public vault;

    function setUp() public {
        vault = Vault(payable(MainnetContracts.YNETHX));
        uint256 previousTotalAssets = vault.totalAssets();

        SetupVault setupVault = new SetupVault();
        setupVault.upgrade();

        // Verify the upgrade was successful
        uint256 newTotalAssets = vault.totalAssets();

        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");

    }

    function test_Vault_Mainnet_upgrade() public {
      assertGt(vault.totalAssets(), 0);
    }
}

