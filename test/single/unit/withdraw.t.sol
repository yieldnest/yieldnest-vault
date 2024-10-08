// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";

contract WithdrawTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    MockERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = MockERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        Etches etches = new Etches();
        etches.mockListaStakeManager();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault(asset);
    }

    function testWithdraw() public {
        address USER = address(33);
        vm.startPrank(USER);
        uint256 amount = 100 * 10 ** 18;
        asset.mint(amount);
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

    function skip_testWithdrawRevertsIfNotApproved() public {
        uint256 amount = 100 * 10 ** 18;
        asset.approve(address(vault), amount);
        vault.deposit(amount, ADMIN);

        uint256 shares = vault.balanceOf(ADMIN);

        vm.expectRevert(abi.encodeWithSelector(IERC20.approve.selector, ADMIN, shares));
        vm.prank(ADMIN);
        vault.withdraw(shares, ADMIN, ADMIN);
    }

    function skip_testWithdrawRevertsIfAmountIsZero() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.withdraw.selector, 0));
        vault.withdraw(0, ADMIN, ADMIN);
    }
}
