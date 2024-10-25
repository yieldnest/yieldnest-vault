// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IERC20} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {MockSTETH} from "test/mocks/MockSTETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultDepositUnitTest is Test, MainnetContracts, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth,) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_deposit(uint256 depositAmount) public {
        // uint256 depositAmount = 100 * 10 ** 18;
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that the vault received the tokens
        assertEq(weth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function test_Vault_depositAsset_STETH(uint256 depositAmount) public {
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        deal(address(steth), alice, depositAmount);

        vm.startPrank(alice);
        steth.approve(address(vault), type(uint256).max);

        uint256 sharesMinted = vault.depositAsset(address(steth), depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that the vault received the tokens
        assertEq(steth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(steth.balanceOf(alice), 0, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");

        vm.stopPrank();
    }

    function test_Vault_mint(uint256 mintAmount) public {
        if (mintAmount < 10) return;
        if (mintAmount > 100_000 ether) return;

        vm.startPrank(alice);
        uint256 sharesMinted = vault.mint(mintAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets did not change
        assertEq(vault.totalAssets(), mintAmount, "Total assets changed incorrectly");

        vm.stopPrank();
    }

    function test_Vault_depositAsset_WrongAsset() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.depositAsset(address(0), 100, alice);
    }

    function test_Vault_depositAssetWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause(true);
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.depositAsset(address(0), 1000, alice);
    }

    function test_Vault_mintWhilePaused() public {
        vm.prank(ADMIN);
        vault.pause(true);
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1000, alice);
    }

    function test_Vault_pauseAndDeposit() public {
        vm.prank(ADMIN);
        vault.pause(true);
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1000, alice);
    }
}
