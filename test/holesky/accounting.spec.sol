// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {HoleskyActors} from "script/Actors.sol";
import {HoleskyContracts} from "script/Contracts.sol";
import {SingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Math} from "src/Common.sol";

contract HoleskyAccountingTest is Test, SetupHelper, HoleskyActors {
    SingleVault public vault;
    WETH9 public asset;
    uint256 public BOOTSTRAP = 1 ether;

    function setUp() public {
        asset = WETH9(payable(HoleskyContracts.WETH));
        vault = createVault();
    }

    function test_Holesky_Vault_totalAssets_initial() public view {
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 1 ether, "Initial total assets should be 1 ether");
    }

    function test_Holesky_Vault_totalAssets_afterDeposit() public {
        uint256 depositAmount = 10 ether;
        address USER = address(33);

        deal(USER, depositAmount);
        vm.startPrank(USER);
        asset.deposit{value: depositAmount}();
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 11 ether, "Total assets should be 11 ether after deposit");
    }

    function test_Holesky_Vault_totalAssets_afterMultipleDeposits() public {
        uint256 depositAmount1 = 5 ether;
        uint256 depositAmount2 = 15 ether;
        address USER1 = address(33);
        address USER2 = address(34);

        deal(USER1, depositAmount1);
        deal(USER2, depositAmount2);

        vm.startPrank(USER1);
        asset.deposit{value: depositAmount1}();
        asset.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1, USER1);
        vm.stopPrank();

        vm.startPrank(USER2);
        asset.deposit{value: depositAmount2}();
        asset.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2, USER2);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 21 ether, "Total assets should be 21 ether after multiple deposits");
    }

    function test_Holesky_Vault_totalAssets_afterWithdrawal() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 5 ether;
        address USER = address(33);

        deal(USER, depositAmount);
        vm.startPrank(USER);
        asset.deposit{value: depositAmount}();
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        vm.startPrank(USER);
        vault.withdraw(withdrawAmount, USER, USER);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 6 ether, "Total assets should be 6 ether after withdrawal");
    }

    function test_Holesky_Vault_totalSupply_afterDeposit() public {
        uint256 depositAmount = 10 ether;
        address USER = address(33);

        deal(USER, depositAmount);
        vm.startPrank(USER);
        asset.deposit{value: depositAmount}();
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, 10 ether + BOOTSTRAP, "Total supply should be 10 ether after deposit");
    }

    function test_Holesky_Vault_totalSupply_afterMultipleDeposits() public {
        uint256 depositAmount1 = 5 ether;
        uint256 depositAmount2 = 15 ether;
        address USER1 = address(33);
        address USER2 = address(34);

        deal(USER1, depositAmount1);
        deal(USER2, depositAmount2);

        vm.startPrank(USER1);
        asset.deposit{value: depositAmount1}();
        asset.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1, USER1);
        vm.stopPrank();

        vm.startPrank(USER2);
        asset.deposit{value: depositAmount2}();
        asset.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2, USER2);
        vm.stopPrank();

        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, 20 ether + BOOTSTRAP, "Total supply should be 20 ether after multiple deposits");
    }

    function test_Holesky_Vault_totalSupply_afterWithdrawal() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 5 ether;
        address USER = address(33);

        deal(USER, depositAmount);
        vm.startPrank(USER);
        asset.deposit{value: depositAmount}();
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        vm.startPrank(USER);
        vault.withdraw(withdrawAmount, USER, USER);
        vm.stopPrank();

        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, 5 ether + BOOTSTRAP, "Total supply should be 5 ether after withdrawal");
    }

    function test_Holesky_Vault_totalAssets_and_totalSupply() public {
        uint256 depositAmount = 10 ether;
        uint256 donationAmount = 5 ether;
        address USER = address(33);
        address DONOR = address(34);

        deal(USER, depositAmount);
        deal(DONOR, donationAmount);

        vm.startPrank(USER);
        asset.deposit{value: depositAmount}();
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, USER);
        vm.stopPrank();

        vm.startPrank(DONOR);
        asset.deposit{value: donationAmount}();
        asset.transfer(address(vault), donationAmount);
        vm.stopPrank();

        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        assertEq(totalSupply, 10 ether + BOOTSTRAP, "Total supply should be 10 ether after deposit and donation");
        assertEq(totalAssets, 15 ether + BOOTSTRAP, "Total assets should be 15 ether after deposit and donation");

        uint256 deposit = vault.totalSupply() * (10 ** 0) / (vault.totalAssets() + 1);
        uint256 withdraw = vault.totalAssets() * (10 ** 0) / (vault.totalSupply() + 1);

        uint256 previewDepositAmount = vault.previewDeposit(deposit);
        uint256 previewMintAmount = vault.previewMint(deposit);
        uint256 previewWithdrawAmount = vault.previewWithdraw(withdraw);
        uint256 previewRedeemAmount = vault.previewRedeem(withdraw);

        assertEq(previewDepositAmount, deposit, "previewDeposit should return the correct deposit amount");
        assertEq(previewMintAmount, deposit, "previewMint should return the correct mint amount");
        assertEq(previewWithdrawAmount, withdraw, "previewWithdraw should return the correct withdraw amount");
        assertEq(previewRedeemAmount, withdraw, "previewRedeem should return the correct redeem amount");
    }
}
