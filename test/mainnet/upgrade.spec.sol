// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

contract VaultMainnetUpgradeTest is BaseIntegrationTest {
    // Implementation addresses
    Vault public vaultImplementation;
    Withdrawer public withdrawerImplementation;

    function setUp() public override {
        super.setUp();
    }

    function upgradeVaultAndWithdrawer() internal {
        {
            vaultImplementation = new Vault();
            UpgradeUtils.timelockUpgrade(
                TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(vaultImplementation)
            );
        }

        {
            withdrawerImplementation = new Withdrawer();
            Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);
            UpgradeUtils.timelockUpgrade(
                TimelockController(payable(TIMELOCK)), ADMIN, address(withdrawer), address(withdrawerImplementation)
            );
        }
    }

    function test_Vault_Upgrade_Implementation_Set_Correctly() public {
        upgradeVaultAndWithdrawer();
        // Verify the vault implementation was upgraded correctly
        address currentVaultImpl = ProxyUtils.getImplementation(address(vault));
        assertEq(currentVaultImpl, address(vaultImplementation), "Vault implementation not set correctly");

        // Verify the withdrawer implementation was upgraded correctly
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);
        address currentWithdrawerImpl = ProxyUtils.getImplementation(address(withdrawer));
        assertEq(
            currentWithdrawerImpl, address(withdrawerImplementation), "Withdrawer implementation not set correctly"
        );
    }

    function test_Vault_Upgrade_ERC20_view_functions() public {
        upgradeVaultAndWithdrawer();

        // Test the name function
        assertEq(vault.name(), "ynETH MAX", "Vault name should be 'YieldNest ETH MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynETHx", "Vault symbol should be 'ynETHx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        uint256 totalSupply = vault.totalSupply();
        assertGt(totalSupply, 0, "Total supply should be greater than zero");
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public {
        upgradeVaultAndWithdrawer();
        // Test the asset function
        assertEq(address(vault.asset()), MC.WETH, "Vault asset should be WETH");

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
        assertEq(assets.length, 11, "There should be 11 assets in the vault");
        assertEq(assets[0], MC.WETH, "First asset should be WETH");
    }

    function test_Vault_Upgrade_totalAssets_unchanged(bool processAccountingBeforeCheck) public {
        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets before upgrade
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Perform the upgrade
        upgradeVaultAndWithdrawer();

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
            totalAssetsAfter,
            totalAssetsBefore,
            1e14,
            "Total assets should be equal within 1e14 (0.0001%) relative error"
        );

        // Assert that totalSupply remains unchanged after the upgrade
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged after upgrade");
    }
}
