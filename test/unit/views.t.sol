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

    function test_Vault_convertToAssetsForAsset_WETH(
        uint256 shares,
        uint256 depositedAssets,
        uint256 rewards
    ) public {
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

        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test WETH conversion
        (uint256 wethAssets, uint256 wethBaseAssets) =
            pVault.convertToAssetsForAsset(MC.WETH, shares, Math.Rounding.Floor);

        uint256 expectedAssets = shares.mulDiv(vault.totalAssets() + 1, vault.totalSupply() + 1, Math.Rounding.Floor);
        assertEq(wethAssets, expectedAssets, "WETH asset conversion failed");
        assertEq(wethBaseAssets, expectedAssets, "WETH base asset conversion failed");
    }

    function test_Vault_convertToAssetsForAsset_WBTC() public view {
        uint256 shares = 1e18;
        
        // Test WBTC conversion (rate set to 20 ETH in setup)
        (uint256 wbtcAssets, uint256 wbtcBaseAssets) =
            pVault.convertToAssetsForAsset(MC.WBTC, shares, Math.Rounding.Floor);
        uint8 wbtcDecimals = IERC20Metadata(MC.WBTC).decimals();
        uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
        assertEq(
            wbtcAssets, (shares * 10 ** wbtcDecimals) / (20 * 10 ** wethDecimals), "WBTC asset conversion failed"
        );
        assertEq(wbtcBaseAssets, shares, "WBTC base asset conversion failed");
    }

    function test_Vault_convertToAssetsForAsset_METH() public view {
        uint256 shares = 1000;

        // Test METH conversion (rate set to 1.2 ETH in setup)
        (uint256 methAssets, uint256 methBaseAssets) =
            pVault.convertToAssetsForAsset(MC.METH, shares, Math.Rounding.Floor);
        assertEq(methAssets, (shares * 10) / 12, "METH asset conversion failed");
        assertEq(methBaseAssets, shares, "METH base asset conversion failed");
    }

    function test_Vault_convertToSharesForAsset() public view {
        uint256 assets = 1000;

        // Test WETH conversion
        (uint256 wethShares, uint256 wethBaseAssets) =
            pVault.convertToSharesForAsset(MC.WETH, assets, Math.Rounding.Floor);
        assertEq(wethShares, assets, "WETH shares conversion failed");
        assertEq(wethBaseAssets, assets, "WETH base asset conversion failed");

        /*
                uint256 baseAssets = _convertAssetToBase(asset_, assets);
        uint256 shares = baseAssets.mulDiv(totalSupply() + 10 ** 0, totalAssets() + 1, rounding);
        return (shares, baseAssets);
        */
        // Test WBTC conversion (rate set to 20 ETH in setup)
        (uint256 wbtcShares, uint256 wbtcBaseAssets) =
            pVault.convertToSharesForAsset(MC.WBTC, assets, Math.Rounding.Floor);
        uint8 wbtcDecimals = IERC20Metadata(MC.WBTC).decimals();
        uint8 wethDecimals = IERC20Metadata(MC.WETH).decimals();
        assertEq(wbtcShares, (assets * 10 ** wethDecimals) * 20 / 10 ** wbtcDecimals, "WBTC shares conversion failed");
        assertEq(
            wbtcBaseAssets, (assets * 20 * 10 ** wethDecimals) / 10 ** wbtcDecimals, "WBTC base asset conversion failed"
        );

        // Test METH conversion (rate set to 1.2 ETH in setup)
        (uint256 methShares, uint256 methBaseAssets) =
            pVault.convertToSharesForAsset(MC.METH, assets, Math.Rounding.Floor);
        assertEq(methShares, (assets * 12) / 10, "METH shares conversion failed");
        assertEq(methBaseAssets, (assets * 12) / 10, "METH base asset conversion failed");
    }

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
