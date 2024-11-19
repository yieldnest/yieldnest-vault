// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultMainnetUpgradeTest is Test, MainnetActors {

    Vault public vault;

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));
        uint256 previousTotalAssets = vault.totalAssets();

        SetupVault setupVault = new SetupVault();
        setupVault.upgrade();

        // Verify the upgrade was successful
        Vault newVault = Vault(payable(MC.YNETHX));
        uint256 newTotalAssets = newVault.totalAssets();

        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");
    }

    function test_Vault_ERC20_view_functions() public {
        // Test the name function
        assertEq(vault.name(), "ynETH MAX", "Vault name should be 'YieldNest ETH MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynETHx", "Vault symbol should be 'ynETHx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        uint256 totalSupply = vault.totalSupply();
        assertGt(totalSupply, 0, "Total supply should be greater than 0");
    }
      
}

