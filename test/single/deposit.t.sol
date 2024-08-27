// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, IERC4626} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";

contract DepositTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        DeployFactory deployFactory = new DeployFactory();
        VaultFactory factory = deployFactory.deploy(0);

        address vaultAddress = factory.createSingleVault(
            asset,
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            0, // time delay
            deployFactory.getProposers(),
            deployFactory.getExecutors()
        );
        vault = SingleVault(payable(vaultAddress));
    }

    function testDeposit() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset
        asset.approve(address(vault), amount);

        uint256 shares = vault.deposit(amount, ADMIN);
        assertEq(shares, amount, "Shares should be equal to the amount deposited");
        assertEq(vault.balanceOf(ADMIN), shares, "Balance of the user should be updated");
        assertEq(asset.balanceOf(address(vault)), amount, "Vault should have received the asset");
        assertEq(vault.totalAssets(), amount, "Vault totalAsset should be amount deposited");
        assertEq(vault.totalSupply(), amount, "Vault totalSupply should be amount deposited");
    }

    function skip_testDepositRevertsIfNotApproved() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset

        vm.expectRevert(abi.encodeWithSelector(IERC20.approve.selector, address(vault), amount));
        vault.deposit(amount, ADMIN);
    }

    function skip_testDepositRevertsIfAmountIsZero() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.deposit.selector, 0));
        vault.deposit(0, ADMIN);
    }
}
