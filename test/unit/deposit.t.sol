// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";

contract VaultDepositUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_deposit_success(uint256 depositAmount) public {
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

    event Log(string, uint256);

    function test_Vault_depositAsset_STETH(uint256 depositAmount) public {
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 ether) return;

        deal(address(steth), alice, depositAmount);

        vm.startPrank(alice);

        uint256 previewDepositAsset = vault.previewDepositAsset(address(steth), depositAmount);

        steth.approve(address(vault), depositAmount);

        uint256 sharesMinted = vault.depositAsset(address(steth), depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");
        assertEq(sharesMinted, previewDepositAsset, "Incorrect shares minted");

        // Check that the vault received the tokens
        assertEq(steth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(steth.balanceOf(alice), 0, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), previewDepositAsset, "Total assets did not increase correctly");

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

    function test_Vault_maxMint() public view {
        uint256 maxMint = vault.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint does not match");
    }

    function test_Vault_previewDeposit() public view {
        uint256 assets = 1000;
        uint256 expectedShares = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, expectedShares, "Preview deposit does not match expected shares");
    }

    function test_Vault_previewMint() public view {
        uint256 shares = 1000;
        uint256 expectedAssets = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, expectedAssets, "Preview mint does not match expected assets");
    }

    function test_Vault_getAsset() public view {
        address assetAddress = MC.WETH;
        IVault.AssetParams memory expectedAssetParams = IVault.AssetParams(true, 0, 18);
        assertEq(vault.getAsset(assetAddress).active, expectedAssetParams.active);
        assertEq(vault.getAsset(assetAddress).index, expectedAssetParams.index);
        assertEq(vault.getAsset(assetAddress).decimals, expectedAssetParams.decimals);
    }

    function test_Vault_maxDeposit() public view {
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, weth.balanceOf(alice), "Max deposit does not match");
    }

    function test_Vault_previewDepositAsset() public view {
        uint256 assets = 1000;
        uint256 expectedShares = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 shares = vault.previewDepositAsset(MC.WETH, assets);
        assertEq(shares, expectedShares, "Preview deposit asset does not match expected shares");
    }

    function test_Vault_previewDepositAsset_WrongAsset() public {
        address invalidAssetAddress = address(0);
        uint256 assets = 1000;
        vm.expectRevert();
        vault.previewDepositAsset(invalidAssetAddress, assets);
    }

    function test_Vault_maxMint_whenPaused_shouldRevert() public {
        // Pause the vault
        vm.prank(ADMIN);
        vault.pause(true);

        // Expect revert when calling maxMint while paused
        assertEq(vault.maxMint(alice), 0, "Should be zero when paused");
    }

    function test_Vault_maxRedeem_whenPaused_shouldRevert() public {
        // Pause the vault
        vm.prank(ADMIN);
        vault.pause(true);

        // Expect revert when calling maxRedeem while paused
        assertEq(vault.maxRedeem(alice), 0, "Should be zero when paused");
    }

    function test_Vault_mintSharesForETH_success() public {
        uint256 initialBalance = address(vault).balance;
        uint256 depositAmount = 1 ether;

        // Send ETH to the vault
        vm.prank(alice);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "ETH transfer failed");

        // Check the vault's balance
        uint256 newBalance = address(vault).balance;
        assertEq(newBalance, initialBalance + depositAmount, "Vault balance mismatch");

        // Check the shares minted
        uint256 sharesMinted = vault.balanceOf(alice);
        assertGt(sharesMinted, 0, "No shares minted");
    }

    function test_Vault_receiveETH(uint256 depositAmount) public {
        if (depositAmount < 1 || depositAmount > 100_000_00 ether) return;
        uint256 initialBalance = address(vault).balance;

        uint256 previewAmount = vault.previewDeposit(depositAmount);

        deal(alice, depositAmount);
        // // Send ETH to the vault
        vm.prank(alice);
        (bool success,) = address(vault).call{value: depositAmount}("");
        require(success, "ETH transfer failed");

        // Check the vault's balance
        uint256 newBalance = address(vault).balance;
        assertEq(newBalance, initialBalance + depositAmount, "Vault balance mismatch");

        // Check the shares minted
        uint256 sharesMinted = vault.balanceOf(alice);
        assertEq(sharesMinted, previewAmount, "No shares minted");
    }

    function test_Vault_receiveETH_zeroValue() public {
        // Send zero ETH to the vault
        vm.prank(alice);
        vm.expectRevert();
        (bool success,) = address(vault).call{value: 0}("");
        require(success, "ETH transfer failed");

        // Check the shares minted
        uint256 sharesMinted = vault.balanceOf(alice);
        assertEq(sharesMinted, 0, "Shares should not be minted for zero value");
    }
}
