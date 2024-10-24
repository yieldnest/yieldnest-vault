// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";

contract VaultDepositUnitTest is Test, MainnetContracts, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

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

    function test_Vault_getAssets() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            IVault.AssetParams memory expectedAssetParams = IVault.AssetParams(true, 0, 18, 0, 0);
            assertEq(vault.getAsset(asset).active, expectedAssetParams.active, "Not active");
            assertEq(vault.getAsset(asset).index, i, "Bad Index");
            assertEq(vault.getAsset(asset).decimals >= 6 || vault.getAsset(asset).decimals <= 18, true, "Bad decimals");
            assertEq(vault.getAsset(asset).idleAssets, expectedAssetParams.idleAssets, "Invalid idleAssets");
            assertEq(vault.getAsset(asset).deployedAssets, expectedAssetParams.deployedAssets, "Invalid deployedAssets");
        }
    }

    function test_Vault_getAsset() public view {
        address assetAddress = address(WETH);
        IVault.AssetParams memory expectedAssetParams = IVault.AssetParams(true, 0, 18, 0, 0);
        assertEq(vault.getAsset(assetAddress).active, expectedAssetParams.active);
        assertEq(vault.getAsset(assetAddress).index, expectedAssetParams.index);
        assertEq(vault.getAsset(assetAddress).decimals, expectedAssetParams.decimals);
        assertEq(vault.getAsset(assetAddress).idleAssets, expectedAssetParams.idleAssets);
        assertEq(vault.getAsset(assetAddress).deployedAssets, expectedAssetParams.deployedAssets);
    }

    function test_Vault_getStrategies() public view {
        address[] memory expectedStrategies = new address[](1);
        expectedStrategies[0] = address(YNETH);
        assertEq(vault.getStrategies().length, expectedStrategies.length);
        for (uint256 i = 0; i < expectedStrategies.length; i++) {
            assertEq(vault.getStrategies()[i], expectedStrategies[i]);
        }
    }

    function test_Vault_getStrategy() public view {
        address strategyAddress = address(YNETH);
        IVault.StrategyParams memory expectedStrategyParams = IVault.StrategyParams(true, 0, 0);
        assertEq(vault.getStrategy(strategyAddress).active, expectedStrategyParams.active);
        assertEq(vault.getStrategy(strategyAddress).index, expectedStrategyParams.index);
        assertEq(vault.getStrategy(strategyAddress).deployedAssets, expectedStrategyParams.deployedAssets);
    }
}
