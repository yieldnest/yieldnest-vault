// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultAdminUintTest is Test, MainnetContracts, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1_000 * 10 ** 18;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth,) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_addStrategy() public {
        address strat = address(42069);
        vm.startPrank(ADMIN);
        vault.addStrategy(strat);
        assertEq(vault.getStrategies().length, 2);
    }

    function test_Vault_addStrategy_unauthorized() public {
        address strat = address(42069);
        vm.expectRevert();
        vault.addStrategy(strat);
    }

    function test_Vault_addAsset() public {
        address asset = address(200);
        vm.startPrank(ADMIN);
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

    function test_Vault_toggleAsset() public {
        address asset = address(33);
        vm.startPrank(ADMIN);
        vault.addAsset(asset, 18);
        IVault.AssetParams memory vaultAsset = vault.getAsset(asset);
        assertEq(vaultAsset.active, true);
        assertEq(vaultAsset.decimals, 18);
        assertEq(vaultAsset.deployedAssets, 0);
        assertEq(vaultAsset.idleAssets, 0);
        vault.toggleAsset(asset, false);
        IVault.AssetParams memory inActiveAsset = vault.getAsset(asset);
        assertEq(inActiveAsset.active, false);
    }

    function test_Vault_toggleAsset_failsIfAssetNotAdded() public {
        address asset = address(3333);
        vm.startPrank(ADMIN);
        vm.expectRevert();
        vault.toggleAsset(asset, false);
    }

    function test_Vault_addStrategy_duplicateAddress() public {
        address strat = address(42069);
        vm.startPrank(ADMIN);
        vault.addStrategy(strat);
        vm.expectRevert();
        vault.addStrategy(strat);
    }

    function test_Vault_addStrategy_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.addStrategy(address(0));
    }

    function test_Vault_setRateProvider() public {
        address rateProvider = address(0x123);
        vm.startPrank(ADMIN);
        vault.setRateProvider(rateProvider);
        assertEq(vault.rateProvider(), rateProvider);
    }

    function test_Vault_setRateProvider_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.setRateProvider(address(0));
    }
}
