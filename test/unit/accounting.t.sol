// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";

contract VaultAccountingUnitTest is Test, MainnetContracts, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
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
        targets[0] = WETH;
        targets[1] = BUFFER_STRATEGY;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.bufferStrategy(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
    }

    function test_Vault_Accounting_convertToShares() public view {
        uint256 assets = 1000 ether;
        uint256 shares = vault.convertToShares(assets);
        assertEq(shares, vault.previewDeposit(assets), "Shares should match previewDeposit");
    }

    function test_Vault_Accounting_convertToAssets() public view {
        uint256 shares = 1000 ether;
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, vault.previewRedeem(shares), "Assets should match previewRedeem");
    }

    function test_Vault_Accounting_totalAssets_afterDeposit() public {
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match the deposit amount");
    }

    function test_Vault_Accounting_totalAssets_afterMultipleDeposits() public {
        uint256 depositAmount1 = 1000 ether;
        uint256 depositAmount2 = 2000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount1, alice);
        vm.prank(alice);
        vault.deposit(depositAmount2, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount1 + depositAmount2, "Total assets should match the sum of deposit amounts");
    }

    function test_Vault_Accounting_totalAssets_afterWithdraw() public {
        uint256 depositAmount = 1000 ether;
        uint256 withdrawAmount = 500 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(
            totalAssets,
            depositAmount - withdrawAmount,
            "Total assets should match the remaining amount after withdrawal"
        );
    }

    function test_Vault_Accounting_totalAssets_afterMultipleWithdrawals() public {
        uint256 depositAmount = 3000 ether;
        uint256 withdrawAmount1 = 1000 ether;
        uint256 withdrawAmount2 = 500 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount1, alice, alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmount2, alice, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(
            totalAssets,
            depositAmount - withdrawAmount1 - withdrawAmount2,
            "Total assets should match the remaining amount after multiple withdrawals"
        );
    }

    function test_Vault_Accounting_totalSupply_afterDeposit() public {
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, depositAmount, "Total supply should match the deposit amount");
    }

    function test_Vault_Accounting_totalSupply_afterMultipleDeposits() public {
        uint256 depositAmount1 = 1000 ether;
        uint256 depositAmount2 = 2000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount1, alice);
        vm.prank(alice);
        vault.deposit(depositAmount2, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, depositAmount1 + depositAmount2, "Total supply should match the sum of deposit amounts");
    }

    function test_Vault_Accounting_totalSupply_afterWithdraw() public {
        uint256 depositAmount = 1000 ether;
        uint256 bufferRatio = 5;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount / bufferRatio);

        vm.prank(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(
            totalSupply, depositAmount - maxWithdraw, "Total supply should match the remaining amount after withdrawal"
        );
    }

    function test_Vault_Accounting_totalSupply_afterMultipleWithdrawals() public {
        uint256 depositAmount = 3000 ether;
        uint256 bufferRatio = 5;

        uint256 withdrawAmount1 = vault.maxWithdraw(alice) / 3;
        uint256 withdrawAmount2 = vault.maxWithdraw(alice) / 7;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount / bufferRatio);

        vm.prank(alice);
        vault.withdraw(withdrawAmount1, alice, alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmount2, alice, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(
            totalSupply,
            depositAmount - withdrawAmount1 - withdrawAmount2,
            "Total supply should match the remaining amount after multiple withdrawals"
        );
    }
}
