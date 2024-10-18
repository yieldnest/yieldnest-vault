// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, IERC4626} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";
import {MainnetContracts} from "script/Contracts.sol";

contract DepositTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    WETH9 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = WETH9(payable(MainnetContracts.WETH));

        Etches etches = new Etches();
        etches.mockWETH9();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault();
    }

    function testDeposit() public {
        uint256 amount = 100 * 10 ** 18; // Assuming 18 decimals for the asset
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
