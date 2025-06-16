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
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VaultMainnetUpgradeTest is BaseIntegrationTest {
    // Implementation addresses
    Vault public vaultImplementation;

    function setUp() public override {
        super.setUp();
    }

    function upgradeVaultAndWithdrawer() internal {
        vaultImplementation = new Vault();

        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(vaultImplementation)
        );
    }

    function test_Vault_Upgrade_Implementation_Set_Correctly() public {
        upgradeVaultAndWithdrawer();
        // Verify the vault implementation was upgraded correctly
        address currentVaultImpl = ProxyUtils.getImplementation(address(vault));
        assertEq(currentVaultImpl, address(vaultImplementation), "Vault implementation not set correctly");
    }

    function test_Vault_Upgrade_ERC20_view_functions() public {
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        upgradeVaultAndWithdrawer();

        // Test the name function
        assertEq(vault.name(), "YieldNest RWA MAX", "Vault name should be 'YieldNest RWA MAX'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynRWAx", "Vault symbol should be 'ynRWAx'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, totalSupplyBefore, "Total supply should be unchanged");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, totalAssetsBefore, "Total assets should be unchanged");

        // Test the defaultAssetIndex function
        uint256 defaultAssetIndex = vault.defaultAssetIndex();
        assertEq(defaultAssetIndex, 1, "Default asset index should be 0 (USDC)");

        // Test the version function
        assertEq(vault.VAULT_VERSION(), "0.3.0", "Vault version should be 0.3.0");

        // Test the provider function
        address provider = vault.provider();
        assertEq(IProvider(provider).getRate(MC.USDC), 1e18, "Provider rate for USDC should be 1e18");
        assertEq(IProvider(provider).getRate(address(wusdc)), 1e18, "Provider rate for wUSDC should be 1e18");

        // Test the paused function
        bool isPaused = vault.paused();
        assertFalse(isPaused, "Vault should not be paused");

        // Test the withdrawal fee
        uint256 withdrawalFee = vault.baseWithdrawalFee();
        assertLe(withdrawalFee, 0.001e8, "Withdrawal fee should be less than or equal to 0.1%");
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public {
        upgradeVaultAndWithdrawer();
        // Test the asset function
        assertEq(address(vault.asset()), MC.USDC, "Vault asset should be USDC");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply / 1e12, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        assertLe(shares / 1e12, amount, "Shares should less or equal to amount deposited");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, amount, 3, "Assets should be greater or equal to shares");

        // Test the maxDeposit function
        uint256 maxDeposit = vault.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        // Test the maxMint function
        uint256 maxMint = vault.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        // Test the maxWithdraw function - reverts because there is no buffer
        vm.expectRevert();
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        //assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        // Test the maxRedeem function
        vm.expectRevert();
        uint256 maxRedeem = vault.maxRedeem(address(this));
        //assertEq(maxRedeem, 0, "Max redeem should be zero");

        // Test the getAssets function
        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 2, "There should be 2 assets in the vault");
        assertEq(assets[0], address(wusdc), "First asset should be WETH");
        assertEq(assets[1], MC.USDC, "Second asset should be USDC");
    }

    function test_Vault_Upgrade_totalAssets_unchanged()
        //bool processAccountingBeforeCheck
        public
    {
        bool processAccountingBeforeCheck = true;

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
            totalAssetsAfter, totalAssetsBefore, 1e16, "Total assets should be equal within 1e16 (1%) relative error"
        );

        // Assert that totalSupply remains unchanged after the upgrade
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged after upgrade");
    }
}
