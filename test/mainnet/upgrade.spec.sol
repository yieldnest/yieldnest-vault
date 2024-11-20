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

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "ynETH MAX", "Vault name should be 'YieldNest ETH MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynETHx", "Vault symbol should be 'ynETHx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        uint256 totalSupply = vault.totalSupply();
        assertGt(totalSupply, 61 ether, "Total supply should be greater than 61 ether");
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
        // Test the asset function
        assertEq(address(vault.asset()), MC.WETH, "Vault asset should be WETH");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 61 ether, "Total assets should be greater than 61 ether");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        assertLe(shares, amount, "Shares should less or equal to assets");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertGe(convertedAssets, amount, "Assets should be greater or equal to shares");

        // Test the maxDeposit function
        uint256 maxDeposit = vault.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        // Test the maxMint function
        uint256 maxMint = vault.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        // Test the maxWithdraw function
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        // Test the maxRedeem function
        uint256 maxRedeem = vault.maxRedeem(address(this));
        assertEq(maxRedeem, 0, "Max redeem should be zero");

        // Test the getAssets function
        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 5, "There should be 4 assets in the vault");
        assertEq(assets[0], MC.WETH, "First asset should be WETH");
        assertEq(assets[1], MC.STETH, "Second asset should be STETH");
        assertEq(assets[2], MC.BUFFER_STRATEGY, "Second asset should be STETH");
        assertEq(assets[3], MC.YNETH, "Third asset should be YNETH");
        assertEq(assets[4], MC.YNLSDE, "Fourth asset should be YNLSDE");
    }
}

