// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {MainnetActors} from "script/Actors.sol";

contract AccessControlTest is Test, MainnetActors, SetupHelper {
    SingleVault public vault;

    function setUp() public {
        vault = createVault();
    }

    function test_Vault_adminRoleSet() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function test_Vault_adminCanGrantRole() public {
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(1));
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(1)), true);
    }

    function skip_test_Vault_nonAdminCannotGrantRole() public {
        vm.startPrank(address(420));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,address)", address(420), vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(4));
    }
}
