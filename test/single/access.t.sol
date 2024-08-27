// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {AccessControlUpgradeable, IAccessControl, IERC20, IAccessControl} from "src/Common.sol";
import {LocalActors} from "script/Actors.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";

contract AccessControlTest is Test, LocalActors, TestConstants {
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

    function testAdminRoleSet() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function testAdminCanGrantRole() public {
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), OPERATOR);
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), OPERATOR), true);
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
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), OPERATOR);
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), OPERATOR));
    }

    function skip_testNonAdminCannotRevokeRole() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), OPERATOR);
    }
}
