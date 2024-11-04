// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {MainnetActors} from "script/Actors.sol";

contract WithdrawTest is Test, SetupHelper, MainnetActors {
    SingleVault public vault;
    WETH9 public asset;

    function setUp() public {
        asset = WETH9(payable(WETH));
        vault = createVault();
    }

    function test_Vault_withdraw() public {
        address USER = address(33);
        vm.startPrank(USER);
        uint256 amount = 100 * 10 ** 18;
        deal(USER, amount);
        asset.deposit{value: amount}();
        asset.approve(address(vault), amount);

        uint256 previousTotalAssets = vault.totalAssets();
        uint256 previousTotalSupply = vault.totalSupply();

        vault.deposit(amount, USER);

        uint256 shares = vault.balanceOf(USER);
        uint256 expectedAssets = vault.convertToAssets(shares);
        uint256 previousBalance = asset.balanceOf(USER);
        uint256 maxAmount = vault.maxWithdraw(USER);
        assertEq(maxAmount, amount);

        uint256 withdrawnShares = vault.withdraw(maxAmount, USER, USER);
        assertEq(shares, withdrawnShares, "User should have withdrawn correct share amount");
        uint256 newNetBalance = asset.balanceOf(USER) - previousBalance;

        assertEq(newNetBalance, expectedAssets, "User should have received the expected amount of assets");
        assertEq(vault.balanceOf(USER), 0, "User's balance in the vault should be zero after withdrawal");
        assertEq(
            vault.totalAssets(), previousTotalAssets, "Vault totalAssets should be previousTotalAssets after withdrawal"
        );
        assertEq(vault.totalSupply(), previousTotalSupply, "Vault totalSupply should be 0 after withdrawal");
        vm.stopPrank();
    }

    function test_Vault_WithdrawPostRewards(
        uint256 amount,
        uint256 rewards
    ) public {

        vm.assume(amount > 0 && amount < 10000 ether);
        vm.assume(rewards >= 0 && rewards < 10000 ether);

        // Pre-deposit
        uint256 preDeposit = 1 ether;
        deal(address(asset), ADMIN, preDeposit);
        vm.startPrank(ADMIN);
        asset.approve(address(vault), preDeposit);
        vault.deposit(preDeposit, ADMIN);
        vm.stopPrank();

        // Simulate rewards being added to vault
        deal(ADMIN, rewards);
        vm.startPrank(ADMIN);
        (bool success2,) = address(asset).call{value: rewards}("");
        require(success2, "ETH transfer failed");
        asset.transfer(address(vault), rewards);
        vm.stopPrank();

        address USER = address(33);

        deal(USER, amount);
        vm.prank(USER);
        (bool success,) = address(vault).call{value: amount}("");
        require(success, "ETH transfer failed");

        uint256 shares = vault.balanceOf(USER);

        vm.prank(USER);
        vault.redeem(shares, USER, USER);

        uint256 postWithdrawBalance = asset.balanceOf(USER);

        assertGe(amount, postWithdrawBalance, "Pre-deposit balance should be greater than or equal to post-withdraw balance");

        uint256 maxLoss = (amount > rewards ? amount : rewards) / 1e18;
        uint256 assetLoss = amount - postWithdrawBalance;
        assertLe(assetLoss, maxLoss + 2, "Asset loss should be less than or equal to maxLoss");
        assertEq(vault.balanceOf(USER), 0, "User's balance in the vault should be zero after withdrawal");
    }
}
