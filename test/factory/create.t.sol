// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, ProxyAdmin} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors, IActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault} from "src/SingleVault.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {Etches} from "test/helpers/Etches.sol";


contract CreateTest is Test, LocalActors, TestConstants {
    VaultFactory public factory;
    IERC20 public asset;
    IActors public actors;
    address[] proposers;
    address[] executors;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        actors = new LocalActors();

        Etches etches = new Etches();
        etches.mockListaStakeManager();

        proposers = [PROPOSER_1, PROPOSER_2];
        executors = [EXECUTOR_1, EXECUTOR_2];

        DeployVaultFactory factoryDeployer = new DeployVaultFactory();
        factory = VaultFactory(factoryDeployer.deployVaultFactory(actors, 0));
    }

    function testCreateSingleVault() public {
        asset.approve(address(factory), 1 ether);
        asset.transfer(address(factory), 1 ether);
        address vault = factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, 0, proposers, executors);
        (,, string memory symbol,) = factory.vaults(vault);
        assertEq(symbol, VAULT_SYMBOL, "Vault timelock should match the expected address");
    }

    function testVaultFactoryAdmin() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function skip_testCreateSingleVaultRevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControl: must have admin role"))));
        factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN, 0, proposers, executors);
    }
}
