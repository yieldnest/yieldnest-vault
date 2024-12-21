// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";

contract VaultMainnetUpgradeTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        vault = setupVault.deploy();

        uint256 previousTotalAssets = vault.totalAssets();

        // TODO: do another upgrade here
        uint256 newTotalAssets = vault.totalAssets();

        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "ynBNB MAX", "Vault name should be 'YieldNest BNB MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynBNBx", "Vault symbol should be 'ynBNBx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.WBNB, "Vault asset should be WBNB");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        assertLe(shares, amount, "Shares should less or equal to amount deposited");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, amount, 3, "Assets should be greater or equal to shares");

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
        assertEq(assets.length, 5, "There should be 5 assets in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
        assertEq(assets[1], MC.BUFFER, "Second asset should be BUFFER");
        assertEq(assets[2], MC.YNBNBk, "Third asset should be YNBNBk");
        assertEq(assets[3], MC.BNBX, "Fourth asset should be BNBX");
        assertEq(assets[4], MC.SLISBNB, "Fifth asset should be SLISBNB");
    }
}
