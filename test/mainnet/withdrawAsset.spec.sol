// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVault} from "src/interface/IVault.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";

contract WithdrawAssetIntegrationTest is BaseIntegrationTest {
    address public withdrawerOperator;

    function setUp() public override {
        super.setUp();

        withdrawerOperator = makeAddr("withdrawerOperator");

        vm.startPrank(ADMIN);
        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), withdrawerOperator);
        vm.stopPrank();
    }

    function test_depositAsset_WBNB_withdrawAsset_WBNB(
        uint256 depositAmount,
        uint256 withdrawAmount,
        bool processAccountingAfterWithdraw
    ) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e15, 1000e18); // 0.001 to 1000 BNB
        withdrawAmount = bound(withdrawAmount, 1, depositAmount - 5); // Can't withdraw more than deposited

        address alice = makeAddr("alice");
        deal(MC.WBNB, alice, depositAmount);

        uint256 allowance = 100_000 ether;

        vm.startPrank(alice);
        IERC20(MC.WBNB).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WBNB, depositAmount, alice);

        IERC20(address(vault)).approve(withdrawerOperator, allowance);
        vm.stopPrank();

        // process accounting before withdrawal
        vault.processAccounting();

        // Store initial state for assertions
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialRate = vault.convertToAssets(1e18); // Rate per share (1 share = X assets)

        vm.startPrank(withdrawerOperator);
        uint256 sharesBurned = vault.withdrawAsset(MC.WBNB, withdrawAmount, alice, alice);
        vm.stopPrank();

        if (processAccountingAfterWithdraw) {
            vault.processAccounting();
        }

        assertEq(IERC20(MC.WBNB).balanceOf(alice), withdrawAmount, "Alice should have withdrawn WBNB");

        assertEq(IERC20(MC.WBNB).balanceOf(withdrawerOperator), 0, "Withdrawer operator should have no WBNB");

        // Assert that the allowance was properly used
        uint256 remainingAllowance = IERC20(address(vault)).allowance(alice, withdrawerOperator);
        assertEq(remainingAllowance, allowance - sharesBurned, "Allowance should be reduced by sharesBurned");

        // Assert rate does not change
        uint256 finalRate = vault.convertToAssets(1e18);
        assertEq(finalRate, initialRate, "Rate should remain unchanged");

        // Assert totalSupply stays the same (shares burned but not from total supply)
        uint256 finalTotalSupply = vault.totalSupply();
        assertEq(finalTotalSupply, initialTotalSupply - sharesBurned, "Total supply should be reduced by shares burned");

        // Assert totalAssets is as expected (reduced by withdrawn amount converted to base)
        uint256 finalTotalAssets = vault.totalAssets();
        uint256 expectedTotalAssets = initialTotalAssets - withdrawAmount; // Assuming WBNB is 1:1 with base asset
        assertEq(finalTotalAssets, expectedTotalAssets, "Total assets should be reduced by withdrawn amount");
    }

    function test_withdrawAsset_multiAsset_BNB(
        uint256 depositAmount,
        uint256 withdrawAmount,
        bool processAccountingAfterWithdraw,
        uint256 assetIndex
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        withdrawAmount = bound(withdrawAmount, 1e15, depositAmount - 1);

        // Define asset list: WBNB and slisBNB
        address[2] memory assets = [MC.WBNB, MC.SLISBNB];
        string[2] memory assetNames = ["WBNB", "slisBNB"];

        // Bound asset index to valid range
        assetIndex = bound(assetIndex, 0, 1);
        address selectedAsset = assets[assetIndex];
        string memory selectedAssetName = assetNames[assetIndex];

        _testWithdrawAssetForAsset(
            selectedAsset, selectedAssetName, depositAmount, withdrawAmount, processAccountingAfterWithdraw
        );
    }

    function _testWithdrawAssetForAsset(
        address asset,
        string memory assetName,
        uint256 depositAmount,
        uint256 withdrawAmount,
        bool processAccountingAfterWithdraw
    ) internal {
        {
            // Enable selected asset deposits
            vm.startPrank(MC.TIMELOCK);
            vault.updateAsset(vault.getAsset(asset).index, IVault.AssetUpdateFields({active: true}));
            vm.stopPrank();
        }

        address alice = makeAddr("alice");
        deal(asset, alice, depositAmount);

        uint256 allowance = 100_000 ether;

        vm.startPrank(alice);
        IERC20(asset).approve(address(vault), depositAmount);
        vault.depositAsset(asset, depositAmount, alice);

        IERC20(address(vault)).approve(withdrawerOperator, allowance);
        vm.stopPrank();

        // process accounting before withdrawal
        vault.processAccounting();

        // Store initial state for assertions
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialRate = vault.convertToAssets(1e18); // Rate per share (1 share = X assets)

        vm.startPrank(withdrawerOperator);
        uint256 sharesBurned = vault.withdrawAsset(asset, withdrawAmount, alice, alice);
        vm.stopPrank();

        if (processAccountingAfterWithdraw) {
            vault.processAccounting();
        }

        assertEq(
            IERC20(asset).balanceOf(alice), withdrawAmount, string.concat("Alice should have withdrawn ", assetName)
        );

        assertEq(
            IERC20(asset).balanceOf(withdrawerOperator),
            0,
            string.concat("Withdrawer operator should have no ", assetName)
        );

        // Assert that the allowance was properly used
        assertEq(
            IERC20(address(vault)).allowance(alice, withdrawerOperator),
            allowance - sharesBurned,
            "Allowance should be reduced by sharesBurned"
        );

        // Assert rate does not change
        assertEq(vault.convertToAssets(1e18), initialRate, "Rate should remain unchanged");

        // Assert totalSupply stays the same (shares burned but not from total supply)
        assertEq(
            vault.totalSupply(), initialTotalSupply - sharesBurned, "Total supply should be reduced by shares burned"
        );

        // Assert totalAssets is as expected (reduced by withdrawn amount converted to base)
        uint256 finalTotalAssets = vault.totalAssets();
        // Convert selected asset to base asset (BNB) for comparison
        uint256 withdrawAmountInBase = ViewUtils.convertAssetToBase(vault, asset, withdrawAmount);
        uint256 expectedTotalAssets = initialTotalAssets - withdrawAmountInBase;
        assertApproxEqAbs(
            finalTotalAssets, expectedTotalAssets, 1, "Total assets should be reduced by withdrawn amount in base"
        );
    }
}
