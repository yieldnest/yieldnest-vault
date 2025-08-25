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
import {console} from "lib/forge-std/src/console.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";

contract VaultViewsUnitTest is Test, Etches, MainnetActors {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    PublicViewsVault public pVault;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        pVault = PublicViewsVault(payable(address(vault)));

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

    function test_Vault_countNativeAsset() public view {
        bool count = vault.countNativeAsset();
        assertEq(count, true, "Count native asset should be true");
    }

    function test_Vault_alwaysComputeTotalAssets() public view {
        assertEq(vault.alwaysComputeTotalAssets(), false, "Always compute total assets should be false");
    }

    function test_Vault_defaultAssetIndex() public view {
        uint256 defaultAssetIndex = vault.defaultAssetIndex();
        assertEq(defaultAssetIndex, 0, "Default asset index should be 0");
    }

    function test_Vault_feeOnTotal() public view {
        uint256 fee = vault._feeOnTotal(1e18, alice);
        assertEq(fee, 0, "Fee on total should be zero");
    }

    function test_Vault_getAssets() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            assertEq(vault.getAsset(asset).index, i, "Bad Index");
            assertEq(vault.getAsset(asset).decimals >= 6 || vault.getAsset(asset).decimals <= 18, true, "Bad decimals");
        }
    }

    function test_Vault_hasAsset() public view {
        // Test that WETH (the main asset) is recognized
        assertTrue(vault.hasAsset(MC.WETH), "WETH should be a valid asset");

        // Test that STETH is recognized (if it's in the asset list)
        assertTrue(vault.hasAsset(MC.STETH), "STETH should be a valid asset");

        // Test that WBTC is recognized (if it's in the asset list)
        assertTrue(vault.hasAsset(MC.WBTC), "WBTC should be a valid asset");

        // Test that METH is recognized (if it's in the asset list)
        assertTrue(vault.hasAsset(MC.METH), "METH should be a valid asset");

        // Test that a random address is not recognized as an asset
        address randomAddress = address(0x1234567890123456789012345678901234567890);
        assertFalse(vault.hasAsset(randomAddress), "Random address should not be a valid asset");

        // Test that zero address is not recognized as an asset
        assertFalse(vault.hasAsset(address(0)), "Zero address should not be a valid asset");
    }

    function test_Vault_hasAsset_afterDeletion(uint256 indexToDelete) public {
        address[] memory assets = vault.getAssets();
        indexToDelete = bound(indexToDelete, 1, assets.length - 1);

        address assetToDelete = assets[indexToDelete];

        // First verify that the asset is initially valid
        assertTrue(vault.hasAsset(assetToDelete), "Asset should initially be valid");

        // Delete the asset (requires ASSET_MANAGER_ROLE)
        vm.startPrank(ASSET_MANAGER);
        vault.deleteAsset(indexToDelete);
        vm.stopPrank();

        // Test that the asset is no longer recognized as valid after deletion
        assertFalse(vault.hasAsset(assetToDelete), "Asset should not be valid after deletion");

        // Verify that all other assets (not the deleted one) are still valid
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] != assetToDelete) {
                assertTrue(vault.hasAsset(assets[i]), "Other assets should still be valid after deletion");
            }
        }
    }

    function test_Vault_hasAsset_afterAddition() public {
        // Create a mock ERC20 token to add as a new asset
        MockERC20 newToken = new MockERC20("New Token", "NEW");
        address newAsset = address(newToken);

        // First verify that the new asset is not initially valid
        assertFalse(vault.hasAsset(newAsset), "New asset should not initially be valid");

        // Add the new asset (requires ASSET_MANAGER_ROLE)
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(newAsset, false);
        vm.stopPrank();

        // Test that the asset is now recognized as valid after addition
        assertTrue(vault.hasAsset(newAsset), "Asset should be valid after addition");

        // Verify that all existing assets are still valid
        address[] memory existingAssets = vault.getAssets();
        for (uint256 i = 0; i < existingAssets.length; i++) {
            if (existingAssets[i] != newAsset) {
                assertTrue(vault.hasAsset(existingAssets[i]), "Existing assets should still be valid after addition");
            }
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
            assertEq(
                assetAmount,
                expectedAssets.mulDiv(10 ** assetDecimals, rate, Math.Rounding.Floor),
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
        vm.assume(assets > 0 && assets <= 100000 ether);
        vm.assume(depositedAssets > 0 && depositedAssets <= 100000 ether);
        vm.assume(rewards >= 0 && rewards <= depositedAssets);

        // Deposit assets through user
        deal(MC.WETH, address(this), depositedAssets);
        IERC20(MC.WETH).approve(address(vault), depositedAssets);
        vault.deposit(depositedAssets, address(vault));

        // Print total shares
        console.log("Deposited Assets:", depositedAssets);
        uint256 totalShares = vault.totalSupply();
        console.log("Total Shares:", totalShares);

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
