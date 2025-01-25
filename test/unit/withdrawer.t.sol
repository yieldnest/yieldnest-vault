// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupWithdrawer} from "test/unit/helpers/SetupWithdrawer.sol";
import {MainnetActors} from "script/Actors.sol";

contract WithdrawerUnitTest is Test, MainnetActors, Etches {
    Withdrawer public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Withdrawer public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupWithdrawer setup = new SetupWithdrawer();
        (vault, weth) = setup.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        vm.startPrank(ADMIN);
        vault.grantRole(vault.ALLOCATOR_ROLE(), alice);
        vault.setHasAllocator(true);
        vm.stopPrank();

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_previewWithdraw(uint256 assets, bool alwaysComputeTotalAssets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 amount = vault.previewWithdrawAsset(MC.WETH, assets);
        assertEq(amount, assets);
    }

    function test_Vault_withdraw_success(uint256 assets, bool alwaysComputeTotalAssets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.prank(alice);
        uint256 depositShares = vault.depositAsset(address(weth), assets, alice);

        vm.prank(ADMIN);
        uint256 previewAmount = vault.previewWithdrawAsset(MC.WETH, assets);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdrawAsset(MC.WETH, assets, alice, alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceBalanceAfter = vault.balanceOf(alice);

        assertEq(aliceBalanceBefore, aliceBalanceAfter + shares, "Alice's balance should be less the shares withdrawn");
        assertEq(previewAmount, shares, "Preview withdraw amount not preview amount");
        assertEq(depositShares, shares, "Deposit shares not match with withdraw shares");
        assertLt(totalAssetsAfter, totalAssetsBefore, "Total assets should be less after withdraw");
        assertEq(
            totalAssetsBefore,
            totalAssetsAfter + assets,
            "Total assets should be total assets after plus assets withdrawn"
        );
    }

    function test_Vault_previewRedeem(uint256 shares, bool alwaysComputeTotalAssets) external {
        if (shares < 2) return;
        if (shares > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 assets = vault.previewWithdrawAsset(MC.WETH, shares);
        assertEq(assets, shares, "Preview Assets response not shares");
    }

    function test_Vault_redeem_success(uint256 amount, bool alwaysComputeTotalAssets) external {
        if (amount < 2) return;
        if (amount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        vm.prank(alice);
        uint256 depositShares = vault.depositAsset(MC.WETH, amount, alice);

        uint256 balanceBefore = weth.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 previewAssets = vault.previewRedeemAsset(MC.WETH, depositShares);

        vm.prank(alice);
        uint256 assetsAfter = vault.redeemAsset(MC.WETH, depositShares, alice, alice);
        uint256 balanceAfter = weth.balanceOf(alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceWethBalanceAfter = weth.balanceOf(alice);

        assertEq(assetsAfter, previewAssets, "assetsAfter = previewAmount");
        assertEq(balanceAfter, balanceBefore + previewAssets, "balanceAfter = balanceBefore + previewAmount");

        assertEq(
            totalAssetsBefore, totalAssetsAfter + previewAssets, "totalAssetsBefore = totalAssetsAfter + previewAmount"
        );
        assertEq(
            aliceWethBalanceBefore,
            aliceWethBalanceAfter,
            "Alice's WETH balance should be increased by the assets withdrawn"
        );
    }

    function test_Vault_withdrawMoreThanBalance() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        vault.depositAsset(MC.WETH, depositAmount, alice);

        // Attempt to withdraw more than the balance
        uint256 excessiveWithdrawAmount = depositAmount + 1 ether;
        vm.expectRevert();
        vault.withdrawAsset(MC.WETH, excessiveWithdrawAmount, alice, alice);
    }

    function test_Vault_redeemMoreThanShareBalance() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        uint256 sharesMinted = vault.depositAsset(MC.WETH, depositAmount, alice);

        // Attempt to redeem more shares than the balance
        uint256 excessiveRedeemAmount = sharesMinted + 1;
        vm.expectRevert();
        vault.redeemAsset(MC.WETH, excessiveRedeemAmount, alice, alice);
    }

    function test_Vault_withdraw_as_non_owner() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        uint256 sharesMinted = vault.depositAsset(MC.WETH, depositAmount, alice);

        // Attempt to withdraw as a non-owner
        vm.startPrank(bob);
        vm.expectRevert();
        vault.withdrawAsset(MC.WETH, sharesMinted, bob, alice);
    }

    function test_Vault_redeemWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeemAsset(MC.WETH, 1000, alice, alice);
    }

    function test_Vault_withdrawWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawAsset(MC.WETH, 1000, alice, alice);
    }

    function test_Vault_maxWithdraw() public view {
        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WETH, alice);
        assertEq(maxWithdraw, 0, "Max withdraw does not match");
    }

    event Log(uint256, string);

    function test_Vault_maxWithdraw_afterDeposit(uint256 depositAmount) public {
        vm.assume(depositAmount > 1000);
        vm.assume(depositAmount < 100_000 ether);

        // Simulate a deposit
        vm.prank(alice);
        vault.depositAsset(MC.WETH, depositAmount, alice);

        // Test maxWithdraw after deposit
        uint256 maxWithdrawAfterDeposit = vault.maxWithdrawAsset(MC.WETH, alice);
        assertEq(maxWithdrawAfterDeposit, depositAmount, "Max withdraw after deposit does not match");
    }

    function test_Vault_maxRedeem() public view {
        uint256 maxRedeem = vault.maxRedeemAsset(MC.WETH, alice);
        assertEq(maxRedeem, 0, "Max redeem does not match");
    }

    function test_Vault_maxRedeem_afterDeposit(uint256 depositAmount) public {
        vm.assume(depositAmount > 1000);
        vm.assume(depositAmount < 100_000 ether);
        vm.prank(alice);
        vault.depositAsset(MC.WETH, depositAmount, alice);

        // Test maxRedeem after deposit
        uint256 maxRedeemAfterDeposit = vault.maxRedeemAsset(MC.WETH, alice);
        assertEq(maxRedeemAfterDeposit, depositAmount, "Max redeem after deposit does not match");
    }

    function test_Vault_maxWithdrawWhenPaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WETH, alice);
        assertEq(maxWithdraw, 0, "Max withdraw is not zero when paused");
    }

    function test_Vault_withdraw_to_different_owner(uint256 depositAmount) public {
        vm.assume(depositAmount > 1000);
        vm.assume(depositAmount < 100_000 ether);

        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, bob);
        vm.stopPrank();

        // Test withdrawal by non-owner (Bob) to Alice
        // vault.approve(alice, depositAmount);
        vm.prank(alice);
        vault.approve(alice, depositAmount);
        vm.expectRevert();
        vault.withdrawAsset(MC.WETH, depositAmount, bob, bob);
    }
}
