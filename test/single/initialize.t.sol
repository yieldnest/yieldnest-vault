// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";

contract InitializeTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    DeployFactory public deployFactory;
    VaultFactory public factory;
    IERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        deployFactory = new DeployFactory();
        factory = deployFactory.deploy(0);

        address vaultAddress = factory.createSingleVault(
            asset,
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            OPERATOR,
            0, // time delay
            deployFactory.getProposers(),
            deployFactory.getExecutors()
        );
        vault = SingleVault(payable(vaultAddress));
    }

    function testInitialize() public {
        SingleVault vaultImplementation = new SingleVault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(vaultImplementation),
            address(this),
            abi.encodeWithSignature(
                "initialize(address,string,string,address,address,uint256,address[],address[])",
                asset,
                VAULT_NAME,
                VAULT_SYMBOL,
                ADMIN,
                OPERATOR,
                0,
                deployFactory.getProposers(),
                deployFactory.getExecutors()
            )
        );

        ISingleVault newVault = ISingleVault(address(proxy));

        assertEq(newVault.asset(), address(asset));
        assertEq(newVault.hasRole(vault.OPERATOR_ROLE(), OPERATOR), true);
        assertEq(newVault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN), true);
        assertEq(newVault.symbol(), VAULT_SYMBOL);
        assertEq(newVault.name(), VAULT_NAME);
    }
}
