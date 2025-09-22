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
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {Provider} from "src/module/Provider.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";

contract VaultMainnetUpgradeTest is BaseIntegrationTest {
    // Implementation addresses
    Vault public vaultImplementation;
    Withdrawer public withdrawerImplementation;

    function setUp() public override {
        super.setUp();
    }

    function upgradeVaultAndWithdrawer() internal {
        {
            vaultImplementation = Vault(payable(new Vault()));
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

        Provider provider = new Provider();
        vm.prank(TIMELOCK);
        vault.setProvider(address(provider));
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

        // Test the defaultAssetIndex function
        uint256 defaultAssetIndex = vault.defaultAssetIndex();
        assertEq(defaultAssetIndex, 0, "Default asset index should be 0 (WETH)");

        // Test the version function
        assertEq(vault.VAULT_VERSION(), "0.4.0", "Vault version should be 0.4.0");

        // Test the buffer function
        address buffer = vault.buffer();
        assertEq(IERC4626(buffer).asset(), MC.WETH, "Buffer asset should be WETH");

        // Test the provider function
        address provider = vault.provider();
        assertEq(IProvider(provider).getRate(MC.WETH), 1e18, "Provider rate for WETH should be 1e18");

        // Test the paused function
        bool isPaused = vault.paused();
        assertFalse(isPaused, "Vault should not be paused");

        // Test the withdrawal fee
        uint256 withdrawalFee = vault.baseWithdrawalFee();
        assertLe(withdrawalFee, 0.0025e8, "Withdrawal fee should be less than or equal to 0.25%");
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public {
        // Get assets before upgrade
        address[] memory assetsBefore = vault.getAssets();

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
        address[] memory assetsAfter = vault.getAssets();
        // Assert assets are the same before and after
        assertEq(assetsAfter.length, assetsBefore.length, "Assets length should be the same before and after upgrade");
        for (uint256 i = 0; i < assetsBefore.length; i++) {
            assertEq(assetsAfter[i], assetsBefore[i], "Asset at index should be the same before and after upgrade");
        }
        assertEq(assetsAfter[0], MC.WETH, "First asset should be WETH");
    }

    function test_Vault_Upgrade_totalAssets_unchanged(bool processAccountingBeforeCheck) public {
        processAccountingBeforeCheck = true;
        if (processAccountingBeforeCheck) {
            vault.processAccounting();
        }

        // Get totalAssets before upgrade
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalSupplyAfter;

        // Perform the upgrade
        upgradeVaultAndWithdrawer();

        uint256 performanceFeeSharesMinted;
        if (processAccountingBeforeCheck) {
            totalSupplyBefore = vault.totalSupply();

            uint256 performanceFeeReceiverBalanceBefore = ViewUtils.getPerformanceFeeReceiverBalance(vault);
            vault.processAccounting();
            uint256 performanceFeeReceiverBalanceAfter = ViewUtils.getPerformanceFeeReceiverBalance(vault);
            performanceFeeSharesMinted = performanceFeeReceiverBalanceAfter - performanceFeeReceiverBalanceBefore;
        }

        // Get totalAssets after upgrade
        uint256 totalAssetsAfter = vault.totalAssets();

        if (performanceFeeSharesMinted > 0) {
            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeSharesMinted),
                (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                100,
                "performance fee shares should be equal to performance fee amount"
            );
        }

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

        totalSupplyAfter = vault.totalSupply();

        // Assert that totalSupply remains unchanged after the upgrade
        assertEq(
            totalSupplyAfter,
            totalSupplyBefore + performanceFeeSharesMinted,
            "Total supply should increase by performanceFeeSharesMinted"
        );
    }
}
