// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

contract VaultMainnetInvariantsTest is BaseIntegrationTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function totalSupplyInvariant(uint256 supply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertApproxEqAbs(
            supply, finalVaultTotalSupply, 5, "Vault totalSupply should be original totalSupply plus additional"
        );
    }

    function totalAssetsInvariant(uint256 assets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            assets, finalVaultTotalAssets, 5, "Vault totalAssets should be original totalAssets plus additional"
        );
    }

    function totalAssetsInvariantRel(uint256 assets, uint256 relativeDelta) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertApproxEqRel(
            assets,
            finalVaultTotalAssets,
            relativeDelta,
            "Vault totalAssets should be original totalAssets plus additional"
        );
    }

    // Use ProcessorUtils for buffer allocation
    function allocateToBuffer(uint256 amount) public {
        ProcessorUtils.allocateToBuffer(vault, amount, PROCESSOR);
    }

    function test_Vault_4626Invariants_depositBase(uint256 assets) public {
        if (assets < 2) return;
        if (assets > 100_000_000 ether) return;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        vault.totalAssets();

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertEqThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        deal(address(this), assets);
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address receiver = address(this);
        uint256 depositedShares = vault.deposit(assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_depositAsset(uint256 assets) public {
        if (assets < 2) return;
        if (assets > 100_000_000 ether) return;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        vault.totalAssets();

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertEqThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address receiver = address(this);
        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_mint(uint256 shares) public {
        if (shares < 2) return;
        if (shares > 10_000 ether) return;

        address alice = address(10);
        vm.label(alice, "Alice");

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        vault.totalAssets();

        // Test the convertToAssets function
        uint256 assets = vault.convertToAssets(shares);
        assertGt(assets, 0, "Assets should be greater than 0");

        deal(alice, assets);

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the converted assets");

        // Test the mint function
        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        uint256 mintedAssets = vault.mint(shares, alice);
        assertEq(mintedAssets, assets, "Minted assets should equal the converted assets");
        vm.stopPrank();

        // Use ProcessorUtils for buffer allocation
        ProcessorUtils.allocateToBuffer(vault, assets, PROCESSOR);

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariantRel(initialAssets + assets, 1e18);
    }

    function test_Vault_4626Invariants_redeem(uint256 assets) public {
        if (assets < 3) return;
        if (assets > 10_000 ether) return;

        address alice = address(420);
        deal(alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        {
            uint256 convertedAssets = vault.convertToAssets(shares);
            assertEqThreshold(convertedAssets, assets, 5, "Converted assets should equal the original assets");
        }

        address baseAsset = vault.asset();

        {
            vm.startPrank(alice);
            (bool success,) = MC.WETH.call{value: assets}("");
            if (!success) revert("Weth deposit failed");
            IERC20(baseAsset).approve(address(vault), assets);
            uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
            assertEqThreshold(depositedShares, shares, 5, "Deposited shares should equal the converted shares");
            vm.stopPrank();
        }

        // hypothetically allocated 100% to the buffer using ProcessorUtils
        ProcessorUtils.allocateToBuffer(vault, assets, PROCESSOR);

        uint256 previewedAssets = vault.previewRedeem(shares);
        uint256 expectedAssets = assets * (1e8 - vault.baseWithdrawalFee()) / 1e8;
        {
            if (assets < 1e14) {
                assertApproxEqAbs(
                    previewedAssets,
                    expectedAssets,
                    1e9,
                    "Previewed redeem assets should equal the original assets minus fee"
                );
            } else {
                assertApproxEqRel(
                    vault.previewRedeem(shares),
                    expectedAssets,
                    1e13,
                    "Previewed redeem assets should equal the original assets minus fee"
                );
            }
        }

        vm.startPrank(alice);
        uint256 redeemableShares = vault.maxRedeem(alice);
        assertEqThreshold(redeemableShares, shares, 5, "Redeemable assets should equal the original assets");

        uint256 initialBalance = IERC20(baseAsset).balanceOf(alice);
        uint256 redeemedAssets = vault.redeem(redeemableShares, alice, alice);
        uint256 finalBalance = IERC20(baseAsset).balanceOf(alice);
        assertApproxEqAbs(previewedAssets, redeemedAssets, 1, "Redeemed assets should match previewed assets");
        assertEqThreshold(
            finalBalance - initialBalance, redeemedAssets, 1, "Final balance should reflect the redeemed assets"
        );
        vm.stopPrank();

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariantRel(initialAssets + (assets - redeemedAssets), 1e18);
    }

    function test_Vault_4626Invariants_withdraw(uint256 assets) public {
        if (assets < 3) return;
        if (assets > 10_000 ether) return;

        address alice = address(10);
        deal(alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        assertGe(shares, 0, "Shares should be greater than 0");

        {
            // Test the convertToAssets function
            uint256 convertedAssets = vault.convertToAssets(shares);
            assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");
        }

        address baseAsset = vault.asset();

        {
            vm.startPrank(alice);
            (bool success,) = MC.WETH.call{value: assets}("");
            if (!success) revert("Weth deposit failed");
            IERC20(baseAsset).approve(address(vault), assets);
            uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
            assertEqThreshold(depositedShares, shares, 3, "Deposited shares should equal the converted shares");
            vm.stopPrank();
        }

        // hypothetically allocated 100% to the buffer using ProcessorUtils
        ProcessorUtils.allocateToBuffer(vault, IERC20(baseAsset).balanceOf(address(vault)), PROCESSOR);

        // Test the previewWithdraw function
        {
            uint256 previewedWithdrawShares = vault.previewWithdraw(assets);
            uint256 expectedPreviewedWithdrawShares = shares * 1e8 / (1e8 - vault.baseWithdrawalFee());
            if (assets < 1e14) {
                assertApproxEqAbs(
                    previewedWithdrawShares,
                    expectedPreviewedWithdrawShares,
                    1e9,
                    "Previewed withdraw shares should equal the original shares"
                );
            } else {
                assertApproxEqRel(
                    previewedWithdrawShares,
                    expectedPreviewedWithdrawShares,
                    1e13,
                    "Previewed withdraw shares should equal the original shares"
                );
            }
        }

        uint256 withdrawableAssets;
        {
            vm.startPrank(alice);

            withdrawableAssets = vault.maxWithdraw(alice);

            uint256 initialBalance = IERC20(baseAsset).balanceOf(alice);
            uint256 withdrawnShares = vault.withdraw(withdrawableAssets, alice, alice);
            assertApproxEqAbs(withdrawnShares, shares, 1, "Withdrawn shares should equal previous shares");
            vm.stopPrank();

            uint256 finalBalance = IERC20(baseAsset).balanceOf(alice);
            assertApproxEqAbs(
                finalBalance - initialBalance, withdrawableAssets, 3, "Final balance should reflect the withdrawn assets"
            );
        }

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariantRel(initialAssets + (assets - withdrawableAssets), 1e18);
    }
}
