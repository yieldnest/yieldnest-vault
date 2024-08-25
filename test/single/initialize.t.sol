// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";

contract InitializeTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        vault = new SingleVault();
    }

    function testInitialize() public {
        vm.prank(address(1));
        vault.initialize(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR);
        assertEq(vault.asset(), address(asset));
        assertEq(vault.hasRole(vault.OPERATOR_ROLE(), OPERATOR), true);
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN), true);
        assertEq(vault.symbol(), VAULT_SYMBOL);
        assertEq(vault.name(), VAULT_NAME);
    }
}
