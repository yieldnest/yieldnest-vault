// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";

contract InitializeTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        Etches etches = new Etches();
        etches.mockWETH9();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault();
    }

    function testInitialize() public {
        SingleVault vaultImplementation = new SingleVault();

        address[] memory proposers = new address[](1);
        proposers[0] = PROPOSER_1;
        address[] memory executors = new address[](1);
        executors[0] = EXECUTOR_1;

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(vaultImplementation),
            address(this),
            abi.encodeWithSignature(
                "initialize(address,string,string,address)",
                asset,
                VAULT_NAME,
                VAULT_SYMBOL,
                ADMIN,
                0,
                proposers,
                executors
            )
        );

        ISingleVault newVault = ISingleVault(address(proxy));

        assertEq(newVault.asset(), address(asset));
        assertEq(newVault.hasRole(vault.DEFAULT_ADMIN_ROLE(), ADMIN), true);
        assertEq(newVault.symbol(), VAULT_SYMBOL);
        assertEq(newVault.name(), VAULT_NAME);
    }
}
