// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {IERC20, ProxyAdmin} from "src/Common.sol";
import {ISingleVault} from "src/interface/ISingleVault.sol";
import {LocalActors, IActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault} from "src/SingleVault.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {Etches} from "test/helpers/Etches.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {AssetHelper} from "test/helpers/Assets.sol";

contract CreateTest is Test, LocalActors, TestConstants {
    VaultFactory public factory;
    IERC20 public asset;
    IActors public actors;
    address[] proposers;
    address[] executors;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(MainnetContracts.WETH));
        actors = new LocalActors();

        Etches etches = new Etches();
        etches.mockWETH9();

        proposers = [PROPOSER_1];
        executors = [EXECUTOR_1];

        DeployVaultFactory factoryDeployer = new DeployVaultFactory();
        factory = VaultFactory(factoryDeployer.deployVaultFactory(actors, 0, MainnetContracts.WETH));
    }

    function testCreateSingleVault() public {
        AssetHelper assetHelper = new AssetHelper();
        assetHelper.get_weth(address(factory), 1 ether);

        address vault = factory.createSingleVault(asset, VAULT_NAME, VAULT_SYMBOL, ADMIN);
        assertEq(ISingleVault(vault).symbol(), VAULT_SYMBOL, "Vault symbol should match");
    }

    function testVaultFactoryAdmin() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), ADMIN));
    }
}
