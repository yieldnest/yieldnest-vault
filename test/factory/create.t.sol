// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, ProxyAdmin} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";
import {SingleVault} from "src/SingleVault.sol";

contract CreateTest is Test, LocalActors, TestConstants {
    VaultFactory public factory;
    IERC20 public asset;
    uint256 minDelay;
    address[] proposers;
    address[] executors;

    function setUp() public {
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        proposers = [PROPOSER_1, PROPOSER_2];
        executors = [EXECUTOR_1, EXECUTOR_2];
        minDelay = 0;
        address singleVaultImpl = address(new SingleVault());
        factory = new VaultFactory(singleVaultImpl, proposers, executors, minDelay, ADMIN);
    }

    function testCreateSingleVault() public {
        vm.startPrank(ADMIN);
        address vault =
            factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR, minDelay, proposers, executors);
        (address vaultAddress,,,) = factory.vaults(VAULT_SYMBOL);
        assertEq(vaultAddress, vault, "Vault address should match the expected address");
    }

    function testVaultFactoryAdmin() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function testProxyOwner() public view {
        ProxyAdmin proxyAdmin = ProxyAdmin(factory.proxyAdmin());
        address proxyOwner = proxyAdmin.owner();
        address timelock = address(factory.timelock());

        assertEq(proxyOwner, timelock);
    }

    function skip_testCreateSingleVaultRevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControl: must have admin role"))));
        factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, OPERATOR, minDelay, proposers, executors);
    }
}
