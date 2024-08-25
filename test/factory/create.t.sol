// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {VaultFactory} from "src/Factory.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";

contract CreateTest is Test, LocalActors, TestConstants {
    VaultFactory public factory;
    IERC20 public asset;

    function setUp() public {
        factory = new VaultFactory();
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
    }

    function testCreateSingleVault() public {
        address vault = factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR);
        (address vaultAddress,,) = factory.vaults(VAULT_SYMBOL);
        assertEq(vaultAddress, vault, "Vault address should match the expected address");
    }

    function skip_testCreateSingleVaultRevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControl: must have admin role"))));
        factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR);
    }
}
