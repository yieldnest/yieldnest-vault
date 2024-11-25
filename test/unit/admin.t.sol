// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract VaultAdminUintTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1_000 * 10 ** 18;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_addAsset() public {
        address asset = address(200);
        vm.prank(ADMIN);
        vault.addAsset(asset, 18);
        assertEq(vault.getAsset(address(200)).active, true);
    }

    function test_Vault_addAsset_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.addAsset(address(0), 18);
    }

    function test_Vault_addAsset_duplicateAddress() public {
        address asset = address(200);
        vm.startPrank(ADMIN);
        vault.addAsset(asset, 18);
        vm.expectRevert();
        vault.addAsset(asset, 18);
    }

    function test_Vault_addAsset_unauthorized() public {
        address asset = address(200);
        vm.expectRevert();
        vault.addAsset(asset, 18);
    }

    function test_Vault_setProvider() public {
        address provider = address(0x123);
        vm.startPrank(ADMIN);
        vault.setProvider(provider);
        assertEq(vault.provider(), provider);
    }

    function test_Vault_setProvider_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.setProvider(address(0));
    }

    function test_Vault_setBuffer_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.setBuffer(address(0));
    }
}
