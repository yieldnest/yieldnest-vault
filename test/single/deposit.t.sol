// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract DepositTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        vault = new SingleVault();

        vm.prank(address(1));
        vault.initialize(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR);
    }

    function testDeposit() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset
        asset.approve(address(vault), amount);

        uint256 shares = vault.deposit(amount, address(this));
        assertEq(shares, amount, "Shares should be equal to the amount deposited");
        assertEq(vault.balanceOf(address(this)), shares, "Balance of the user should be updated");
        assertEq(asset.balanceOf(address(vault)), amount, "Vault should have received the asset");
        assertEq(vault.totalAssets(), amount, "Vault totalAsset should be amount deposited");
        assertEq(vault.totalSupply(), amount, "Vault totalSupply should be amount deposited");
    }

    function skip_testDepositRevertsIfNotApproved() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset

        vm.expectRevert(abi.encodeWithSelector(IERC20.approve.selector, address(vault), amount));
        vault.deposit(amount, address(this));
    }

    function skip_testDepositRevertsIfAmountIsZero() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.deposit.selector, 0));
        vault.deposit(0, address(this));
    }
}
