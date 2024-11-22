// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {TestUtils} from "test/mainnet/helpers/TestUtils.sol";

contract VaultMainnetInvariantsTest is Test, TestUtils, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER_STRATEGY;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.bufferStrategy(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
        vault.processAccounting();
    }

    function test_Vault_4626Invariants_deposit(uint256 assets) public {
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
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
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
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

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

    function test_Vault_4626Invariants_redeem(uint256 assets) public {
        if (assets < 3) return;
        if (assets > 100_000_000 ether) return;
        
        address alice = address(420);
        deal(alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        address baseAsset = vault.asset();

        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
        assertThreshold(depositedShares, shares, 3, "Deposited shares should equal the converted shares");
        vm.stopPrank();


        // hypothetically allocated 100% to the buffer
        allocateToBuffer(assets);

        // Test the previewRedeem function
        uint256 previewedRedeemAssets = vault.previewRedeem(shares);
        assertThreshold(previewedRedeemAssets, assets, 3, "Previewed redeem assets should equal the original assets");

        vm.startPrank(alice);
        uint256 redeemableShares = vault.maxRedeem(alice);
        assertThreshold(redeemableShares, shares, 3, "Redeemable assets should equal the original assets");

        uint256 initialBalance = IERC20(baseAsset).balanceOf(alice);
        uint256 redeemedAssets = vault.redeem(redeemableShares, alice, alice);
        uint256 finalBalance = IERC20(baseAsset).balanceOf(alice);
        assertThreshold(redeemedAssets, assets, 3, "Redeemed assets should equal the original assets");
        assertThreshold(finalBalance - initialBalance, assets, 3, "Final balance should reflect the redeemed assets");
        vm.stopPrank();

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariant(initialAssets);
    }

    function test_Vault_4626Invariants_withdraw(uint256 assets) public {
        if (assets < 3) return;
        if (assets > 100_000_000 ether) return;

        address alice = address(420);
        deal(alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        assertGe(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        address baseAsset = vault.asset();

        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
        assertThreshold(depositedShares, shares, 3, "Deposited shares should equal the converted shares");
        vm.stopPrank();

        // hypothetically allocated 100% to the buffer
        allocateToBuffer(IERC20(baseAsset).balanceOf(address(vault)));
        vault.processAccounting();

        // Test the previewWithdraw function
        uint256 previewedWithdrawShares = vault.previewWithdraw(assets);
        assertThreshold(previewedWithdrawShares, shares, 3, "Previewed withdraw shares should equal the original shares");
        
        vm.startPrank(alice);
    
        uint256 withdrawableAssets = vault.maxWithdraw(alice);
        assertThreshold(withdrawableAssets, assets, 3, "Withdrawable assets should equal the original shares");

        uint256 withdrawnShares = vault.withdraw(withdrawableAssets, alice, alice);
        assertThreshold(withdrawnShares, shares, 3, "Withdrawn shares should equal previous shares");
        vm.stopPrank();

        uint256 finalBalance = IERC20(baseAsset).balanceOf(alice);
        assertThreshold(finalBalance, assets, 3, "Final balance should reflect the withdrawn assets");

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariant(initialAssets);
    }

    function totalSupplyInvariant(uint256 initialSupply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertThreshold(initialSupply, finalVaultTotalSupply, 3, "Vault totalSupply should be original totalSupply");
    }

    function totalAssetsInvariant(uint256 initialAssets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertThreshold(initialAssets, finalVaultTotalAssets, 3, "Vault totalAssets should be original totalAssets");
    }
}