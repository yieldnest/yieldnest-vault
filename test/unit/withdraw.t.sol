// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultWithdrawUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
    }

    function test_Vault_previewWithdraw(uint256 assets, bool alwaysComputeTotalAssets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 amount = vault.previewWithdraw(assets);
        assertEq(amount, assets);
    }

    function test_Vault_withdraw_success(uint256 assets, bool alwaysComputeTotalAssets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.prank(alice);
        uint256 depositShares = vault.deposit(assets, alice);

        vm.prank(ADMIN);
        allocateToBuffer(assets);
        uint256 previewAmount = vault.previewWithdraw(assets);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdraw(assets, alice, alice);
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

        uint256 assets = vault.previewWithdraw(shares);
        assertEq(assets, shares, "Preview Assets response not shares");
    }

    function test_Vault_redeem_success(uint256 amount, bool alwaysComputeTotalAssets) external {
        if (amount < 2) return;
        if (amount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        vm.prank(alice);
        uint256 depositShares = vault.deposit(amount, alice);

        allocateToBuffer(amount);

        uint256 balanceBefore = weth.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 previewAssets = vault.previewRedeem(depositShares);

        vm.prank(alice);
        uint256 assetsAfter = vault.redeem(depositShares, alice, alice);
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
        vault.deposit(depositAmount, alice);

        // Attempt to withdraw more than the balance
        uint256 excessiveWithdrawAmount = depositAmount + 1 ether;
        vm.expectRevert();
        vault.withdraw(excessiveWithdrawAmount, alice, alice);
    }

    function test_Vault_redeemMoreThanShareBalance() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Attempt to redeem more shares than the balance
        uint256 excessiveRedeemAmount = sharesMinted + 1;
        vm.expectRevert();
        vault.redeem(excessiveRedeemAmount, alice, alice);
    }

    function test_Vault_withdraw_as_non_owner() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Attempt to withdraw as a non-owner
        vm.startPrank(bob);
        vm.expectRevert();
        vault.withdraw(sharesMinted, bob, alice);
    }

    function test_Vault_redeemWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1000, alice, alice);
    }

    function test_Vault_withdrawWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1000, alice, alice);
    }

    function test_Vault_withdrawUsingBufferBalance() public {
        /*

            This is just a simple unit test for the buffer.
            Proper testing for the varios situations
            are in scenario tests.

        */
        uint256 depositAmount = 100 ether;
        IERC20 buffer = IERC20(MC.BUFFER);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Give bob base asset tokens
        deal(bob, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(bob, INITIAL_BALANCE);

        vm.startPrank(bob);
        weth.approve(address(vault), type(uint256).max);

        vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Vault balance should be 200 ether;

        assertEq(weth.balanceOf(address(vault)), 200 ether);

        // this is a processAllocation call to transfer the assets
        // bob and alice deposited to the buffer strategy
        allocateToBuffer(150 ether);

        // weth balance of buffer should be 150 ether
        assertEq(buffer.balanceOf(address(vault)), 150 * 10 ** 18, "Buffer balance before != 150 ether");

        // weth balance of vault should be 50 ether
        assertEq(weth.balanceOf(address(vault)), 50 ether, "Wrong weth balance in vault");

        // Now processing with test:
        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(100 ether, alice, alice);

        assertEq(weth.balanceOf(alice), aliceWethBalanceBefore + 100 ether, "Alice's weth balance is not 100 ether");
        assertEq(buffer.balanceOf(address(vault)), 50 ether, "Buffer balance is not 100 ether");
        assertEq(weth.balanceOf(address(vault)), 50 ether, "Buffer balance is not 100 ether");
        // Check that the buffer balance is now zero
    }

    function test_Vault_maxWithdraw() public view {
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        assertEq(maxWithdraw, 0, "Max withdraw does not match");
    }

    event Log(uint256, string);

    function test_Vault_maxWithdraw_afterDeposit() public {
        uint256 depositAmount = 1212121212;
        // if (depositAmount < 10) return;
        // if (depositAmount > 99_000) return;

        // Simulate a deposit
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Process allocation to send assets to the buffer
        allocateToBuffer(depositAmount);

        // Test maxWithdraw after deposit
        uint256 maxWithdrawAfterDeposit = vault.maxWithdraw(alice);
        assertEq(maxWithdrawAfterDeposit, depositAmount, "Max withdraw after deposit does not match");
    }

    function test_Vault_maxRedeem() public view {
        uint256 maxRedeem = vault.maxRedeem(alice);
        assertEq(maxRedeem, 0, "Max redeem does not match");
    }

    function test_Vault_maxRedeem_afterDeposit() public {
        // Simulate a deposit
        uint256 depositAmount = 1000;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);
        // Test maxRedeem after deposit
        uint256 maxRedeemAfterDeposit = vault.maxRedeem(alice);
        assertEq(maxRedeemAfterDeposit, depositAmount, "Max redeem after deposit does not match");
    }

    function test_Vault_maxWithdrawWhenPaused() public {
        vm.prank(ADMIN);
        vault.pause();
        assertEq(vault.paused(), true);

        uint256 maxWithdraw = vault.maxWithdraw(alice);
        assertEq(maxWithdraw, 0, "Max withdraw is not zero when paused");
    }

    function test_Vault_withdraw_to_different_owner() public {
        uint256 depositAmount = 1000;
        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Process allocation to send assets to the buffer
        allocateToBuffer(depositAmount);

        // Test withdrawal by non-owner (Bob) to Alice
        // vault.approve(alice, depositAmount);
        vm.prank(alice);
        vault.approve(alice, depositAmount);
        vm.expectRevert();
        vault.withdraw(depositAmount, bob, bob);
    }
}
