// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {MainnetActors} from "script/Actors.sol";
import {SingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {MainnetContracts} from "script/Contracts.sol";

contract DepositTest is Test, SetupHelper, MainnetActors {
    SingleVault public vault;
    WETH9 public asset;

    function setUp() public {
        asset = WETH9(payable(MainnetContracts.WETH));
        vault = createVault();
    }

    function test_Vault_Deposit(uint256 amount) public {
        if (amount < 1) return;
        if (amount > 1_000_000 ether) return;

        asset.deposit{value: amount}();
        asset.approve(address(vault), amount);
        address USER = address(33);

        uint256 previewAmount = vault.previewDeposit(amount);
        uint256 shares = vault.deposit(amount, USER);

        uint256 totalShares = vault.convertToShares(amount + 1 ether);

        assertEq(shares, previewAmount, "Shares should be equal to the amount deposited");
        assertEq(vault.balanceOf(USER), shares, "Balance of the user should be updated");
        assertEq(asset.balanceOf(address(vault)), amount + 1 ether, "Vault should have received the asset");
        assertEq(vault.totalAssets(), amount + 1 ether, "Vault totalAsset should be amount deposited");
        assertEq(vault.totalSupply(), totalShares, "Vault totalSupply should be amount deposited");

        // Additional invariant tests
        assertEq(vault.convertToAssets(shares), amount, "Converted assets should match the deposited amount");
        assertEq(vault.maxDeposit(USER), type(uint256).max, "Max deposit for user should be unlimited");
        assertEq(vault.maxMint(USER), type(uint256).max, "Max mint for user should be unlimited");
        assertEq(vault.maxWithdraw(USER), shares, "Max withdraw for user should be equal to shares");
        assertEq(vault.maxRedeem(USER), shares, "Max redeem for user should be equal to shares");
    }

    function test_Vault_DepositETH(uint256 amount) public {
        if (amount < 1) return;
        if (amount > 1_000_000 ether) return;

        uint256 bootstrap = 1 ether;
        address USER = address(33);

        deal(USER, amount);

        // Deposit ETH directly to the vault
        vm.prank(USER);
        (bool success,) = address(vault).call{value: amount}("");
        if (!success) revert("WETH Deposit failed");

        uint256 totalShares = vault.convertToShares(amount);

        assertEq(vault.balanceOf(USER), totalShares, "Balance of the user should be updated");
        assertEq(asset.balanceOf(address(vault)) - bootstrap, amount, "Vault should have received the ETH");
        assertEq(vault.totalAssets(), amount + bootstrap, "Vault totalAssets should be amount deposited");
        assertEq(vault.totalSupply(), totalShares + bootstrap, "Vault totalSupply should be amount deposited");

        // Additional invariant tests
        assertEq(vault.convertToAssets(totalShares), amount, "Converted assets should match the deposited amount");
        assertEq(vault.maxDeposit(USER), type(uint256).max, "Max deposit for user should be unlimited");
        assertEq(vault.maxMint(USER), type(uint256).max, "Max mint for user should be unlimited");
        assertEq(vault.maxWithdraw(USER), totalShares, "Max withdraw for user should be equal to total shares");
        assertEq(vault.maxRedeem(USER), totalShares, "Max redeem for user should be equal to total shares");
    }

    function test_Vault_RandomDepositsAndWithdrawals() public {
        uint256 numOperations = 10000;
        address USER = address(33);
        uint256 totalDeposited = 0;
        uint256 totalWithdrawn = 0;
        uint256 bootstrap = 1 ether;

        for (uint256 i = 0; i < numOperations; i++) {
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 2;
            uint256 amount = uint256(keccak256(abi.encodePacked(block.timestamp, i, USER))) % 100 ether;

            if (operation == 0) {
                // Random ETH deposit
                deal(USER, amount);
                vm.prank(USER);
                (bool success,) = address(vault).call{value: amount}("");
                if (!success) revert("ETH Deposit failed");
                totalDeposited += amount;
            } else {
                // Random WETH deposit
                deal(USER, amount);
                vm.startPrank(USER);
                asset.deposit{value: amount}();
                IERC20(address(asset)).approve(address(vault), amount);
                vault.deposit(amount, USER);
                vm.stopPrank();
                totalDeposited += amount;
            }

            // Random withdrawal
            uint256 shares = vault.balanceOf(USER);
            if (shares > 0) {
                uint256 withdrawAmount = uint256(keccak256(abi.encodePacked(block.timestamp, i, USER, shares))) % shares;
                vm.prank(USER);
                vault.withdraw(withdrawAmount, USER, USER);
                totalWithdrawn += withdrawAmount;
            }
        }

        uint256 finalBalance = vault.balanceOf(USER);
        uint256 finalTotalAssets = vault.totalAssets();
        uint256 finalTotalSupply = vault.totalSupply();

        // Assertions
        assertEq(
            finalTotalAssets,
            totalDeposited - totalWithdrawn + bootstrap,
            "Final total assets should match the net deposited amount"
        );
        assertEq(finalTotalSupply, finalBalance + bootstrap, "Final total supply should match the user's balance");
    }
}
