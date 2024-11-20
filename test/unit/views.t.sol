// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";

contract VaultDepositUnitTest is Test, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

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

    function test_Vault_asset() public view {
        address expectedAsset = MC.WETH;
        assertEq(vault.asset(), expectedAsset, "Asset address does not match");
    }

    function test_Vault_decimals() public view {
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18);
    }

    function test_Vault_getAssets() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            IVault.AssetParams memory expectedAssetParams = IVault.AssetParams(true, 0, 18, 0);
            assertEq(vault.getAsset(asset).active, expectedAssetParams.active, "Not active");
            assertEq(vault.getAsset(asset).index, i, "Bad Index");
            assertEq(vault.getAsset(asset).decimals >= 6 || vault.getAsset(asset).decimals <= 18, true, "Bad decimals");
            assertEq(vault.getAsset(asset).idleBalance, expectedAssetParams.idleBalance, "Invalid idleAssets");
        }
    }

    function test_Vault_convertToShares() public view {
        uint256 amount = 1000;
        uint256 shares = vault.convertToShares(amount);
        assertEq(shares, amount, "Conversion to shares failed");
    }

    function test_Vault_convertToAssets() public view {
        uint256 shares = 1000;
        uint256 amount = vault.convertToAssets(shares);
        assertEq(amount, shares, "Conversion to assets failed");
    }

    function test_Vault_getStrategies() public view {
        address[] memory expectedStrategies = new address[](1);
        expectedStrategies[0] = MC.BUFFER_STRATEGY;
        assertEq(vault.getStrategies().length, expectedStrategies.length);
        for (uint256 i = 0; i < expectedStrategies.length; i++) {
            assertEq(vault.getStrategies()[i], expectedStrategies[i]);
        }
    }

    function test_Vault_getStrategy() public view {
        address strategyAddress = MC.BUFFER_STRATEGY;
        IVault.StrategyParams memory expectedStrategyParams = IVault.StrategyParams(true, 0, 18, 0);
        assertEq(vault.getStrategy(strategyAddress).active, expectedStrategyParams.active);
        assertEq(vault.getStrategy(strategyAddress).index, expectedStrategyParams.index);
        assertEq(vault.getStrategy(strategyAddress).idleBalance, expectedStrategyParams.idleBalance);
    }

    function test_Vault_rateProvider() public view {
        assertEq(vault.rateProvider(), MC.ETH_RATE_PROVIDER, "Rate provider does not match expected");
    }

    function test_Vault_bufferStrategy() public view {
        assertEq(vault.bufferStrategy(), MC.BUFFER_STRATEGY, "Buffer strategy does not match expected");
    }
}
