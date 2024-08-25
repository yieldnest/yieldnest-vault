// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    AccessControlUpgradeable,
    IAccessControl
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {LocalActors} from "script/Actors.sol";

contract AccessControlTest is Test, LocalActors {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        asset = IERC20(address(new MockERC20("Test Asset", "TST")));
        vault = new SingleVault();

        vm.prank(address(1));
        vault.initialize(asset, "Test Vault", "ynTEST", ADMIN, OPERATOR);
    }

    function testAdminRoleSet() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function testAdminCanGrantRole() public {
        vm.startPrank(ADMIN);
        vault.grantRole(vault.OPERATOR_ROLE(), OPERATOR);
        assertEq(vault.hasRole(vault.OPERATOR_ROLE(), OPERATOR), true);
    }

    function skip_testNonAdminCannotGrantRole() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.grantRole(vault.OPERATOR_ROLE(), address(4));
    }

    function testAdminCanRevokeRole() public {
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.OPERATOR_ROLE(), OPERATOR);
        assertFalse(vault.hasRole(vault.OPERATOR_ROLE(), OPERATOR));
    }

    function skip_testNonAdminCannotRevokeRole() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.revokeRole(vault.OPERATOR_ROLE(), OPERATOR);
    }
}
