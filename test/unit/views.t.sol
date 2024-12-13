// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {Math} from "src/Common.sol";
import {IERC20, IERC20Metadata} from "src/Common.sol";

contract VaultViewsUnitTest is Test, Etches {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    PublicViewsVault pVault;

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

        pVault = PublicViewsVault(payable(address(vault)));
    }

    function test_Vault_asset() public view {
        address expectedAsset = MC.WETH;
        assertEq(vault.asset(), expectedAsset, "Asset address does not match");
    }

    function test_Vault_decimals() public view {
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18);
    }

    function test_Vault_countNativeAsset() public view {
        bool count = vault.countNativeAsset();
        assertEq(count, true, "Count native asset should be true");
    }

    function test_Vault_getAssets() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            assertEq(vault.getAsset(asset).index, i, "Bad Index");
            assertEq(vault.getAsset(asset).decimals >= 6 || vault.getAsset(asset).decimals <= 18, true, "Bad decimals");
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

    function test_Vault_Provider() public view {
        assertEq(vault.provider(), MC.PROVIDER, "Provider does not match expected");
    }

    function test_Vault_Buffer_public() public view {
        assertEq(vault.buffer(), MC.BUFFER, "Buffer strategy does not match expected");
    }

    function _testConvertToAssetsForAsset(
        address asset,
        uint256 shares,
        uint256 depositedAssets,
        uint256 rewards,
        uint256 rate
    ) internal {
        vm.assume(shares > 0 && shares <= 100000 ether);
        vm.assume(depositedAssets > 0 && depositedAssets <= 100000 ether);
        vm.assume(rewards >= 0 && rewards <= depositedAssets);

        // Deposit assets through user
        deal(MC.WETH, address(this), depositedAssets);
        IERC20(MC.WETH).approve(address(vault), depositedAssets);
        vault.deposit(depositedAssets, address(vault));

        deal(MC.WETH, address(this), rewards);
        IERC20(MC.WETH).transfer(address(vault), rewards);

        // Process accounting to update total assets
        vault.processAccounting();

        // Test asset conversion
        (uint256 assetAmount, uint256 baseAssets) = pVault.convertToAssetsForAsset(asset, shares, Math.Rounding.Floor);

        uint256 expectedAssets = shares.mulDiv(vault.totalAssets() + 1, vault.totalSupply() + 1, Math.Rounding.Floor);

        if (asset == MC.WETH) {
            assertEq(assetAmount, expectedAssets, "WETH asset conversion failed");
            assertEq(baseAssets, expectedAssets, "WETH base asset conversion failed");
        } else {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            // Example For WBTC:
            // If expectedAssets = 100 ETH = 100e18 wei
            // assetDecimals = 8 (WBTC decimals)
            // rate = 20e18 (20 ETH per WBTC)
            // Then: assetAmount = (100e18 * 1e8) / 20e18 = 5 WBTC = 500000000 satoshi
            assertEq(assetAmount, (expectedAssets * 10 ** assetDecimals) / rate, "Asset conversion failed");
            assertEq(baseAssets, expectedAssets, "Base asset conversion failed");
        }
    }

    function test_Vault_convertToAssetsForAsset_WETH(uint256 shares, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToAssetsForAsset(MC.WETH, shares, depositedAssets, rewards, 1e18);
    }

    function test_Vault_convertToAssetsForAsset_WBTC(uint256 shares, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToAssetsForAsset(MC.WBTC, shares, depositedAssets, rewards, 20e18);
    }

    function test_Vault_convertToAssetsForAsset_METH(uint256 shares, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToAssetsForAsset(MC.METH, shares, depositedAssets, rewards, 12e17);
    }

    function _testConvertToSharesForAsset(
        address asset,
        uint256 assets,
        uint256 depositedAssets,
        uint256 rewards,
        uint256 rate
    ) internal {
        vm.assume(assets > 0 && assets <= 100000 ether);
        vm.assume(depositedAssets > 0 && depositedAssets <= 100000 ether);
        vm.assume(rewards >= 0 && rewards <= depositedAssets);

        // Deposit assets through user
        deal(MC.WETH, address(this), depositedAssets);
        IERC20(MC.WETH).approve(address(vault), depositedAssets);
        vault.deposit(depositedAssets, address(vault));

        deal(MC.WETH, address(this), rewards);
        IERC20(MC.WETH).transfer(address(vault), rewards);

        // Process accounting to update total assets
        vault.processAccounting();

        // Test asset conversion
        (uint256 shares, uint256 baseAssets) = pVault.convertToSharesForAsset(asset, assets, Math.Rounding.Floor);

        uint256 expectedShares =
            baseAssets.mulDiv(vault.totalSupply() + 1, vault.totalAssets() + 1, Math.Rounding.Floor);

        if (asset == MC.WETH) {
            assertEq(shares, expectedShares, "WETH shares conversion failed");
            assertEq(baseAssets, assets, "WETH base asset conversion failed");
        } else {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            // For WBTC example:
            // If assets = 5 WBTC = 500000000 satoshi (8 decimals)
            // rate = 20e18 (WBTC/ETH price)
            // Then: baseAssets = (500000000 * 20e18) / 1e8 = 100e18 ETH
            assertEq(shares, expectedShares, "Shares conversion failed");
            assertEq(baseAssets, (assets * rate) / 10 ** assetDecimals, "Base asset conversion failed");
        }
    }

    function test_Vault_convertToSharesForAsset_WETH(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToSharesForAsset(MC.WETH, assets, depositedAssets, rewards, 1e18);
    }

    function test_Vault_convertToSharesForAsset_WBTC(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToSharesForAsset(MC.WBTC, assets, depositedAssets, rewards, 20e18);
    }

    function test_Vault_convertToSharesForAsset_METH(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
        _testConvertToSharesForAsset(MC.METH, assets, depositedAssets, rewards, 12e17);
    }

    function _testConvertAssetToBase(address asset, uint256 assets, uint256 rate) internal view {
        vm.assume(assets > 0 && assets <= 100000 ether);

        uint256 baseAssets = pVault.convertAssetToBase(asset, assets);

        if (asset == MC.WETH) {
            assertEq(baseAssets, assets, "WETH to base conversion failed");
        } else {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            // For WBTC example:
            // If assets = 5 WBTC = 500000000 satoshi (8 decimals)
            // rate = 20e18 (WBTC/ETH price)
            // Then: baseAssets = (500000000 * 20e18) / 1e8 = 100e18 ETH
            assertEq(baseAssets, (assets * rate) / 10 ** assetDecimals, "Asset to base conversion failed");
        }
    }

    function test_Vault_convertAssetToBase_WETH(uint256 assets) public view {
        _testConvertAssetToBase(MC.WETH, assets, 1e18);
    }

    function test_Vault_convertAssetToBase_WBTC(uint256 assets) public view {
        _testConvertAssetToBase(MC.WBTC, assets, 20e18);
    }

    function test_Vault_convertAssetToBase_METH(uint256 assets) public view {
        _testConvertAssetToBase(MC.METH, assets, 12e17);
    }

    function _testConvertBaseToAsset(address asset, uint256 baseAssets, uint256 rate) internal view {
        vm.assume(baseAssets > 0 && baseAssets <= 100000 ether);

        uint256 assets = pVault.convertBaseToAsset(asset, baseAssets);

        if (asset == MC.WETH) {
            assertEq(assets, baseAssets, "Base to WETH conversion failed");
        } else {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            // Example For WBTC:
            // If baseAssets = 100 ETH = 100e18 wei
            // assetDecimals = 8 (WBTC decimals)
            // rate = 20e18 (20 ETH per WBTC)
            // Then: assets = (100e18 * 1e8) / 20e18 = 5 WBTC = 500000000 satoshi
            assertEq(assets, (baseAssets * 10 ** assetDecimals) / (rate), "Base to asset conversion failed");
        }
    }

    function test_Vault_convertBaseToAsset_WETH(uint256 baseAssets) public view {
        _testConvertBaseToAsset(MC.WETH, baseAssets, 1e18);
    }

    function test_Vault_convertBaseToAsset_WBTC(uint256 baseAssets) public view {
        _testConvertBaseToAsset(MC.WBTC, baseAssets, 20e18);
    }

    function test_Vault_convertBaseToAsset_METH(uint256 baseAssets) public view {
        _testConvertBaseToAsset(MC.METH, baseAssets, 12e17);
    }
}
