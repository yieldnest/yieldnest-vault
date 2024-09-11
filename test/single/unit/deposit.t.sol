// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, IERC4626} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/IVaultFactory.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";


contract DepositTest is Test, LocalActors, TestConstants {
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

    function testDeposit() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset
        asset.mint(amount);
        asset.approve(address(vault), amount);
        address USER = address(33);

        uint256 previewAmount = vault.previewDeposit(amount);
        uint256 shares = vault.deposit(amount, USER);

        uint256 totalShares = vault.convertToShares(amount + 1 ether);

        assertEq(shares, previewAmount, "Shares should be equal to the amount deposited");
        assertEq(vault.balanceOf(USER), shares, "Balance of the user should be updated");
        assertEq(asset.balanceOf(address(vault)), amount + 1 ether, "Vault should have received the asset");
        assertEq(vault.totalAssets(), ((amount + 1 ether) * 1.02 ether) / 1 ether, "Vault totalAsset should be amount deposited");
        assertEq(vault.totalSupply(), totalShares, "Vault totalSupply should be amount deposited");
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
