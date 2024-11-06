// SPDX-License-Identifier: BSD-3-Clauses
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {MainnetActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {SetupHelper} from "test/helpers/Setup.sol";

contract InitializeTest is Test, SetupHelper, MainnetActors, TestConstants {
    SingleVault public vault;
    WETH9 public asset;

    function setUp() public {
        asset = WETH9(payable(WETH));
        vault = createVault();
    }

    function test_Vault_initialize() public {
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
