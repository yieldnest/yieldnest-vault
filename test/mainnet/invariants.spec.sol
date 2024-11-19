// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";

contract VaultMainnetInvariantsTest is Test, MainnetActors {

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
    }

    function test_Vault_4626Invariants_deposit(uint256 assets) public {
        if (assets < 1) return;
        if (assets > 100_000_000 ether) return;

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
        assertEq(convertedAssets, assets, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertEq(previewedShares, shares, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEq(previewedAssets, assets, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address receiver = address(this);
        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        // Test the processAccounting function
        vault.processAccounting();
        uint256 newTotalAssets = vault.totalAssets();
        assertEq(newTotalAssets, totalAssets + assets, "New total assets should equal deposit amount plus original total assets");
    
    }

    function test_Vault_4626Invariants_redeem(uint256 assets) public {
        if (assets < 1) return;
        if (assets > 100_000_000 ether) return;
        
        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEq(convertedAssets, assets, "Converted assets should equal the original assets");

        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address assetAddress = vault.asset();
        address receiver = address(this);

        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        // hypothetically allocated 100% to the buffer
        allocateToBuffer(assets);

        // Test the redeem function
        uint256 redeemableAssets = vault.previewRedeem(shares);
        assertEq(redeemableAssets, assets, "Redeemable assets should equal the original assets");

        uint256 initialBalance = IERC20(assetAddress).balanceOf(address(this));
        uint256 redeemedAssets = vault.redeem(shares, address(this), address(this));
        uint256 finalBalance = IERC20(assetAddress).balanceOf(address(this));
        assertEq(redeemedAssets, assets, "Redeemed assets should equal the original assets");
        assertEq(finalBalance - initialBalance, assets, "Final balance should reflect the redeemed assets");

        // // Test the withdraw function
        // uint256 withdrawableShares = vault.previewWithdraw(assets);
        // assertEq(withdrawableShares, shares, "Withdrawable shares should equal the original shares");

        // initialBalance = IERC20(assetAddress).balanceOf(address(this));
        // uint256 withdrawnAssets = vault.withdraw(assets, address(this), address(this));
        // finalBalance = IERC20(assetAddress).balanceOf(address(this));
        // assertEq(withdrawnAssets, assets, "Withdrawn assets should equal the original assets");
        // assertEq(finalBalance - initialBalance, assets, "Final balance should reflect the withdrawn assets");
    }

    function test_Vault_4626Invariants_withdraw(uint256 assets) public {
        if (assets < 1) return;
        if (assets > 100_000_000 ether) return;
        
        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEq(convertedAssets, assets, "Converted assets should equal the original assets");

        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address assetAddress = vault.asset();
        address receiver = address(this);

        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        // hypothetically allocated 100% to the buffer
        allocateToBuffer(assets);

        // Test the withdraw function
        uint256 withdrawableShares = vault.previewWithdraw(assets);
        assertEq(withdrawableShares, shares, "Withdrawable shares should equal the original shares");

        uint256 initialBalance = IERC20(assetAddress).balanceOf(address(this));
        uint256 withdrawnAssets = vault.withdraw(assets, address(this), address(this));
        uint256 finalBalance = IERC20(assetAddress).balanceOf(address(this));
        assertEq(withdrawnAssets, assets, "Withdrawn assets should equal the original assets");
        assertEq(finalBalance - initialBalance, assets, "Final balance should reflect the withdrawn assets");
    }    
}