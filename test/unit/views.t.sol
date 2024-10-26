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
        address expectedAsset = address(WETH);
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

    function test_Vault_maxDeposit() public view {
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max, "Max deposit does not match");
    }

    function test_Vault_maxMint() public view {
        uint256 maxMint = vault.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint does not match");
    }

    function test_Vault_maxWithdraw() public view {
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        assertEq(maxWithdraw, 0, "Max withdraw does not match");
    }

    function test_Vault_maxWithdraw_afterDeposit() public {
        // Simulate a deposit
        uint256 depositAmount = 1000;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test maxWithdraw after deposit
        uint256 maxWithdrawAfterDeposit = vault.maxWithdraw(alice);
        assertEq(maxWithdrawAfterDeposit, depositAmount, "Max withdraw after deposit does not match");
    }

    function test_Vault_maxRedeem() public view {
        uint256 maxRedeem = vault.maxRedeem(alice);
        assertEq(maxRedeem, 0, "Max redeem does not match");
    }

    function test_Vault_maxRedeem_afterDeposit() public {
        // Simulate a deposit
        uint256 depositAmount = 1000;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test maxRedeem after deposit
        uint256 maxRedeemAfterDeposit = vault.maxRedeem(alice);
        assertEq(maxRedeemAfterDeposit, depositAmount, "Max redeem after deposit does not match");
    }

    function test_Vault_previewDeposit() public view {
        uint256 assets = 1000;
        uint256 expectedShares = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, expectedShares, "Preview deposit does not match expected shares");
    }

    function test_Vault_previewMint() public view {
        uint256 shares = 1000;
        uint256 expectedAssets = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, expectedAssets, "Preview mint does not match expected assets");
    }

    function test_Vault_getAsset() public view {
        address assetAddress = address(WETH);
        IVault.AssetParams memory expectedAssetParams = IVault.AssetParams(true, 0, 18, 0);
        assertEq(vault.getAsset(assetAddress).active, expectedAssetParams.active);
        assertEq(vault.getAsset(assetAddress).index, expectedAssetParams.index);
        assertEq(vault.getAsset(assetAddress).decimals, expectedAssetParams.decimals);
        assertEq(vault.getAsset(assetAddress).idleBalance, expectedAssetParams.idleBalance);
    }

    function test_Vault_getStrategies() public view {
        address[] memory expectedStrategies = new address[](3);
        expectedStrategies[0] = address(BUFFER_STRATEGY);
        expectedStrategies[1] = address(YNETH);
        expectedStrategies[2] = address(YNLSDE);
        assertEq(vault.getStrategies().length, expectedStrategies.length);
        for (uint256 i = 0; i < expectedStrategies.length; i++) {
            assertEq(vault.getStrategies()[i], expectedStrategies[i]);
        }
    }

    function test_Vault_getStrategy() public view {
        address strategyAddress = address(YNETH);
        IVault.StrategyParams memory expectedStrategyParams = IVault.StrategyParams(true, 1, 18, 0);
        assertEq(vault.getStrategy(strategyAddress).active, expectedStrategyParams.active);
        assertEq(vault.getStrategy(strategyAddress).index, expectedStrategyParams.index);
        assertEq(vault.getStrategy(strategyAddress).idleBalance, expectedStrategyParams.idleBalance);
    }

    function test_Vault_previewDepositAsset() public view {
        uint256 assets = 1000;
        uint256 expectedShares = 1000; // Assuming a 1:1 conversion for simplicity
        uint256 shares = vault.previewDepositAsset(address(WETH), assets);
        assertEq(shares, expectedShares, "Preview deposit asset does not match expected shares");
    }

    function test_Vault_previewDepositAsset_WrongAsset() public {
        address invalidAssetAddress = address(0);
        uint256 assets = 1000;
        vm.expectRevert();
        vault.previewDepositAsset(invalidAssetAddress, assets);
    }

    function test_Vault_rateProvider() public view {
        assertEq(vault.rateProvider(), ETH_RATE_PROVIDER, "Rate provider does not match expected");
    }

    function test_Vault_bufferStrategy() public view {
        assertEq(vault.bufferStrategy(), BUFFER_STRATEGY, "Buffer strategy does not match expected");
    }
}
