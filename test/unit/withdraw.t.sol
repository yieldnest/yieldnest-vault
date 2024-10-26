// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultWithdrawUnitTest is Test, MainnetContracts, MainnetActors, Etches {
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

    function test_Vault_previewWithdraw(uint256 assets) external view {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;
        uint256 amount = vault.previewWithdraw(assets);
        assertEq(amount, assets);
    }

    function test_Vault_withdraw_success(uint256 assets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.startPrank(alice);
        uint256 depositShares = vault.deposit(assets, alice);
        uint256 previewAmount = vault.previewWithdraw(assets);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();
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

    function test_Vault_previewRedeem(uint256 shares) external view {
        if (shares < 2) return;
        if (shares > 100_000 ether) return;
        uint256 assets = vault.previewWithdraw(shares);
        assertEq(assets, shares, "Preview Assets response not shares");
    }

    function test_Vault_redeem_success(uint256 amount) external {
        if (amount < 2) return;
        if (amount > 100_000 ether) return;

        vm.startPrank(alice);
        uint256 depositShares = vault.deposit(amount, alice);

        uint256 balanceBefore = weth.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 previewAmount = vault.previewRedeem(depositShares);
        uint256 assetsAfter = vault.redeem(depositShares, alice, alice);
        uint256 balanceAfter = weth.balanceOf(alice);
        uint256 totalAssetsAfter = vault.totalAssets();

        assertEq(assetsAfter, previewAmount, "assetsAfter = previewAmount");
        assertEq(balanceAfter, balanceBefore + previewAmount, "balanceAfter = balanceBefore + previewAmount");

        assertEq(
            totalAssetsBefore, totalAssetsAfter + previewAmount, "totalAssetsBefore = totalAssetsAfter + previewAmount"
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
        vault.pause(true);
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1000, alice, alice);
    }

    function test_Vault_withdrawWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause(true);
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

        vm.prank(alice);
        uint256 aliceSharesMinted = vault.deposit(depositAmount, alice);

        // Give bob base asset tokens
        deal(bob, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(bob, INITIAL_BALANCE);

        vm.startPrank(bob);
        weth.approve(address(vault), type(uint256).max);

        uint256 bobSharesMinted = vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // this is a processAllocation call to transfer the assets
        // bob and alice deposited to the buffer strategy
        vm.prank(ADMIN);
        address[] memory targets = new address[](2);
        targets[0] = WETH;
        targets[1] = vault.bufferStrategy();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(BUFFER_STRATEGY), 150 ether);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", 150 ether, address(vault));

        vm.prank(ADMIN);
        vault.processAllocation(targets, values, data);

        // weth balance of buffer should be 150 ether
        assertEq(
            IERC20(BUFFER_STRATEGY).balanceOf(address(vault)), 150 * 10 ** 18, "Buffer balance before is not 150 ether"
        );

        // weth balance of vault should be 50 ether
        assertEq(weth.balanceOf(address(vault)), 50 ether, "Wrong weth balance in vault");

        // Now processing with test:
        // the valut should pull 50 ether, and use the 50 ether in the vault to send alice
        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(100 ether, alice, alice);

        assertEq(weth.balanceOf(alice), aliceWethBalanceBefore + 100 ether, "Alice's weth balance is not 100 ether");
        assertEq(weth.balanceOf(address(vault)), 0 ether, "Vault weth balance is not 50 ether");
        assertEq(IERC20(BUFFER_STRATEGY).balanceOf(address(vault)), 100 ether, "Buffer balance is not 100 ether");
        // Check that the buffer balance is now zero
    }
}
