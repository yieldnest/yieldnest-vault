// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract WithdrawTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        vault = new SingleVault();

        vm.prank(address(1));
        vault.initialize(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR);
    }

    function testWithdraw() public {
        uint256 amount = 100 * 10 ** 18;
        asset.approve(address(vault), amount);
        vault.deposit(amount, address(this));

        uint256 shares = vault.balanceOf(address(this));
        uint256 expectedAssets = vault.convertToAssets(shares);
        uint256 previousBalance = asset.balanceOf(address(this));

        uint256 assetsReceived = vault.withdraw(shares, address(this), address(this));
        uint256 newNetBalance = asset.balanceOf(address(this)) - previousBalance;

        assertEq(assetsReceived, expectedAssets, "Assets received should be equal to the expected amount");
        assertEq(newNetBalance, expectedAssets, "User should have received the expected amount of assets");
        assertEq(vault.balanceOf(address(this)), 0, "User's balance in the vault should be zero after withdrawal");
        assertEq(vault.totalAssets(), 0, "Vault totalAssets should be zero after withdrawal");
        assertEq(vault.totalSupply(), 0, "Vault totalSupply should be zero after withdrawal");
    }

    function skip_testWithdrawRevertsIfNotApproved() public {
        uint256 amount = 100 * 10 ** 18;
        asset.approve(address(vault), amount);
        vault.deposit(amount, address(this));

        uint256 shares = vault.balanceOf(address(this));

        vm.expectRevert(abi.encodeWithSelector(IERC20.approve.selector, address(vault), shares));
        vm.prank(address(this));
        vault.withdraw(shares, address(this), address(this));
    }

    function skip_testWithdrawRevertsIfAmountIsZero() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.withdraw.selector, 0));
        vault.withdraw(0, address(this), address(this));
    }
}
