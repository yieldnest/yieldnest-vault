// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract VaultMainnetUpgradeTest is BaseIntegrationTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "ynBNB MAX", "Vault name should be 'ynBNB MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynBNBx", "Vault symbol should be 'ynBNBx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();

        // Test the balanceOf function
        vault.balanceOf(address(this));

        // Test the defaultAssetIndex function
        assertEq(vault.defaultAssetIndex(), 0, "Default asset index should be 0");

        assertEq(IERC4626(vault.buffer()).asset(), MC.WBNB, "Buffer asset should be WBNB");

        // Test the provider rate for WBNB
        assertEq(Provider(vault.provider()).getRate(MC.WBNB), 1e18, "Provider rate for WBNB should be 1e18");

        // Test the version function
        assertEq(vault.VAULT_VERSION(), "0.4.0", "Vault version should be '0.4.0'");
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
        assertEq(assets.length, 8, "There should be 8 assets in the vault");
    }

    function test_Vault_Upgrade_totalAssets_unchanged(bool processAccountingBeforeCheck) public {
        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets before upgrade
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Perform the upgrade
        upgradeVaults();

        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets after upgrade
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // Assert that totalAssets after upgrade is greater than or equal to totalAssets before upgrade
        assertGe(
            totalAssetsAfter,
            totalAssetsBefore,
            "Total assets after upgrade should be greater than or equal to total assets before upgrade"
        );

        // Increase due to sfrxETH and potentially other assets that accumulate rewards in a streaming fashion
        assertApproxEqRel(
            totalAssetsAfter, totalAssetsBefore, 1e16, "Total assets should be equal within 1e16 (1%) relative error"
        );

        // Assert that totalSupply remains unchanged after the upgrade
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged after upgrade");
    }
}
