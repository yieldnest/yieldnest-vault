// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";

contract WithdrawTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        DeployFactory deployFactory = new DeployFactory();
        VaultFactory factory = deployFactory.deploy(0);
        asset.approve(address(factory), 1 ether);
        asset.transfer(address(factory), 1 ether);
        address vaultAddress = factory.createSingleVault(
            asset,
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            0, // admin tx time delay
            deployFactory.getProposers(),
            deployFactory.getExecutors()
        );
        vault = SingleVault(payable(vaultAddress));
    }

    function testWithdraw() public {
        vm.startPrank(ADMIN);
        uint256 amount = 100 * 10 ** 18;
        asset.approve(address(vault), amount);
        vault.deposit(amount, ADMIN);

        uint256 shares = vault.balanceOf(ADMIN);
        uint256 expectedAssets = vault.convertToAssets(shares);
        uint256 previousBalance = asset.balanceOf(ADMIN);

        uint256 assetsReceived = vault.withdraw(shares, ADMIN, ADMIN);
        uint256 newNetBalance = asset.balanceOf(ADMIN) - previousBalance;

        assertEq(assetsReceived, expectedAssets, "Assets received should be equal to the expected amount");
        assertEq(newNetBalance, expectedAssets, "User should have received the expected amount of assets");
        assertEq(vault.balanceOf(ADMIN), 0, "User's balance in the vault should be zero after withdrawal");
        assertEq(vault.totalAssets(), 1 ether, "Vault totalAssets should be 1 ether after withdrawal");
        assertEq(vault.totalSupply(), 1 ether, "Vault totalSupply should be 1 ether after withdrawal");
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
