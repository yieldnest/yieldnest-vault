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
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
            uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
            assertEq(
                assetAmount,
                (expectedAssets * 10 ** assetDecimals) / rate,
                "Asset conversion failed"
            );
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

        if (asset == MC.WETH) {
            assertEq(shares, assets, "WETH shares conversion failed");
            assertEq(baseAssets, assets, "WETH base asset conversion failed");
        } else {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
            assertEq(
                shares,
                (assets * rate * 10 ** wethDecimals) / 10 ** assetDecimals,
                "Shares conversion failed"
            );
            assertEq(
                baseAssets,
                (assets * rate * 10 ** wethDecimals) / 10 ** assetDecimals,
                "Base asset conversion failed"
            );
        }
    }

    // function test_Vault_convertToSharesForAsset_WETH(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
    //     _testConvertToSharesForAsset(MC.WETH, assets, depositedAssets, rewards, 1);
    // }

    // function test_Vault_convertToSharesForAsset_WBTC(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
    //     _testConvertToSharesForAsset(MC.WBTC, assets, depositedAssets, rewards, 20);
    // }

    // function test_Vault_convertToSharesForAsset_METH(uint256 assets, uint256 depositedAssets, uint256 rewards) public {
    //     _testConvertToSharesForAsset(MC.METH, assets, depositedAssets, rewards, 12);
    // }

    function test_Vault_convertAssetToBase() public view {
        uint256 assets = 1000;

        // Test WETH conversion
        uint256 wethBase = pVault.convertAssetToBase(MC.WETH, assets);
        assertEq(wethBase, assets, "WETH to base conversion failed");

        // Test WBTC conversion (rate set to 20 ETH in setup)
        uint256 wbtcBase = pVault.convertAssetToBase(MC.WBTC, assets);
        uint8 wbtcDecimals = IERC20Metadata(MC.WBTC).decimals();
        uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
        assertEq(wbtcBase, (assets * 20 * 10 ** wethDecimals) / 10 ** wbtcDecimals, "WBTC to base conversion failed");

        // Test METH conversion (rate set to 1.2 ETH in setup)
        uint256 methBase = pVault.convertAssetToBase(MC.METH, assets);
        assertEq(methBase, (assets * 12) / 10, "METH to base conversion failed");
    }

    function test_Vault_convertBaseToAsset() public view {
        uint256 baseAssets = 1e18;

        // Test WETH conversion
        uint256 wethAssets = pVault.convertBaseToAsset(MC.WETH, baseAssets);
        assertEq(wethAssets, baseAssets, "Base to WETH conversion failed");

        // Test WBTC conversion (rate set to 20 ETH in setup)
        uint256 wbtcAssets = pVault.convertBaseToAsset(MC.WBTC, baseAssets);
        uint8 wbtcDecimals = IERC20Metadata(MC.WBTC).decimals();
        uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
        assertEq(
            wbtcAssets, (baseAssets * 10 ** wbtcDecimals) / (20 * 10 ** wethDecimals), "Base to WBTC conversion failed"
        );

        // Test METH conversion (rate set to 1.2 ETH in setup)
        uint256 methAssets = pVault.convertBaseToAsset(MC.METH, baseAssets);
        assertEq(methAssets, (baseAssets * 10) / 12, "Base to METH conversion failed");
    }
}
