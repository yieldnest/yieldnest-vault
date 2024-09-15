// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {AccessControlUpgradeable, IAccessControl, IERC20, IAccessControl} from "src/Common.sol";
import {LocalActors} from "script/Actors.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";

contract AccessControlTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        Etches etches = new Etches();
        etches.mockListaStakeManager();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault(asset);
    }

    function testAdminRoleSet() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function testAdminCanGrantRole() public {
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(1));
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(1)), true);
    }

    function skip_testNonAdminCannotGrantRole() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(4));
    }

    function testAdminCanRevokeRole() public {
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(1));
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(1)));
    }

    function skip_testNonAdminCannotRevokeRole() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(1));
    }
}
