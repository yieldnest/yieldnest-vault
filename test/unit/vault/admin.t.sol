// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IAccessControl} from "src/Common.sol";
import {MockERC20CustomDecimals} from "test/unit/mocks/MockERC20CustomDecimals.sol";

contract VaultAdminUintTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockERC20 public asset;
    MockERC20 public asset2;
    MockERC20 public asset3;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1_000 * 10 ** 18;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Deploy mock asset
        asset = new MockERC20("Mock Token", "MOCK");
        asset2 = new MockERC20("Mock Token 2", "MOCK2");
        asset3 = new MockERC20("Mock Token 3", "MOCK3");
        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        deal(address(weth), address(alice), INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_addAsset() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        assertEq(vault.getAsset(address(asset)).active, true);
    }

    function test_Vault_addAsset_notActive() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), false);
        assertEq(vault.getAsset(address(asset)).active, false);
    }

    function test_Vault_addAsset_nullAddress() public {
        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        vault.addAsset(address(0), true);
    }

    function test_Vault_addAsset_duplicateAddress() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(asset)));
        vault.addAsset(address(asset), true);
    }

    function test_Vault_addAsset_primaryDepositAssetDuplicate() public {
        // Add a primary deposit asset (first asset in the list)
        vm.startPrank(ASSET_MANAGER);

        address baseAsset = vault.asset();
        // Verify duplicate asset error
        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, baseAsset));
        vault.addAsset(baseAsset, true);

        vm.stopPrank();
    }

    function test_Vault_addAsset_unauthorized() public {
        vm.expectRevert();
        vault.addAsset(address(asset), true);
    }

    function test_Vault_updateAsset(bool initialActiveStatus, bool updateActiveStatus) public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), initialActiveStatus);

        // Get initial values
        IVault.AssetParams memory initialParams = vault.getAsset(address(asset));
        uint256 initialIndex = initialParams.index;
        uint8 initialDecimals = initialParams.decimals;

        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: updateActiveStatus});

        uint256 index = vault.getAsset(address(asset)).index;
        vault.updateAsset(index, fields);

        // Assert active changed but index and decimals stayed same
        IVault.AssetParams memory finalParams = vault.getAsset(address(asset));
        assertEq(finalParams.active, updateActiveStatus);
        assertEq(finalParams.index, initialIndex);
        assertEq(finalParams.decimals, initialDecimals);
    }

    function test_Vault_updateAsset_invalidIndex() public {
        uint256 invalidIndex = vault.getAssets().length;
        vm.startPrank(ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAsset.selector, address(0)));
        vault.updateAsset(invalidIndex, IVault.AssetUpdateFields({active: true}));
        vm.stopPrank();
    }

    function test_Vault_updateAsset_unauthorized() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), vault.ASSET_MANAGER_ROLE()
            )
        );
        vault.updateAsset(0, IVault.AssetUpdateFields({active: false}));
    }

    function test_Vault_deleteAsset_unauthorized() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), vault.ASSET_MANAGER_ROLE()
            )
        );
        vault.deleteAsset(0);
    }

    function test_Vault_deleteAsset_BaseAsset() public {
        vm.prank(ASSET_MANAGER);
        vm.expectRevert(IVault.BaseAsset.selector);
        vault.deleteAsset(0);
    }

    function test_Vault_deleteAsset_DefaultAsset() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // Initialize with defaultAssetIndex = 1
        newVault.initialize(address(this), "Test Vault", "TV", 18, 0, true, false, 1);

        // Grant asset manager role
        newVault.grantRole(newVault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);

        // Add assets
        vm.startPrank(ASSET_MANAGER);
        newVault.addAsset(address(asset), true); // index 0
        newVault.addAsset(address(asset2), true); // index 1 (default asset)
        vm.stopPrank();

        // Verify default asset index
        assertEq(newVault.defaultAssetIndex(), 1, "Default asset index should be 1");

        // Try to delete the default asset
        vm.prank(ASSET_MANAGER);
        vm.expectRevert(IVault.DefaultAsset.selector);
        newVault.deleteAsset(1);
    }

    function test_Vault_deleteAsset_invalidIndex() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);

        uint256 invalidIndex = vault.getAssets().length;
        vm.startPrank(ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAsset.selector, address(0)));
        vault.deleteAsset(invalidIndex);
        vm.stopPrank();
    }

    function test_Vault_deleteAsset_success() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vault.addAsset(address(asset2), true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 8);

        vm.startPrank(ASSET_MANAGER);
        vault.deleteAsset(1);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 7);
    }

    function test_Vault_deleteAsset_updatesIndex() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vault.addAsset(address(asset2), true);
        vault.addAsset(address(asset3), true);
        vm.stopPrank();

        uint256 initialAssetsCount = vault.getAssets().length;
        assertEq(vault.getAssets().length, initialAssetsCount, "Initial assets count should match");

        // Get index of asset to delete
        address[] memory assets = vault.getAssets();
        uint256 assetIndex;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(asset)) {
                assetIndex = i;
                break;
            }
        }

        // Store asset params before deletion
        IVault.AssetParams[] memory beforeStates = new IVault.AssetParams[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            beforeStates[i] = vault.getAsset(assets[i]);
        }

        // Delete asset
        vm.startPrank(ASSET_MANAGER);
        vault.deleteAsset(assetIndex);
        vm.stopPrank();

        uint256 expectedAssetsCount = initialAssetsCount - 1;
        assertEq(vault.getAssets().length, expectedAssetsCount, "Assets count should decrease by 1 after deletion");

        // Get updated assets and compare with before states
        address[] memory updatedAssets = vault.getAssets();
        for (uint256 i = 0; i < updatedAssets.length; i++) {
            IVault.AssetParams memory currentParams = vault.getAsset(updatedAssets[i]);

            if (i == assetIndex) {
                // The asset at the deleted index should now be the last asset from before
                assertEq(updatedAssets[i], address(asset3), "Asset3 should be moved to the deleted asset's position");
                assertEq(currentParams.index, assetIndex, "Asset3's index should be updated to the deleted position");
            } else {
                // Assets before the deleted index should remain unchanged
                assertEq(updatedAssets[i], assets[i], "Assets before deleted index should remain in same position");
                assertEq(currentParams.index, beforeStates[i].index, "Index should remain unchanged");
            }
        }

        // Verify the deleted asset is no longer active and its index is wiped out
        assertFalse(vault.getAsset(address(asset)).active, "Deleted asset should not be active anymore");
        assertEq(vault.getAsset(address(asset)).index, 0, "Deleted asset's index should be reset to 0");
    }

    function test_Vault_deleteAsset_lastAsset() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vault.addAsset(address(asset2), true);
        vault.addAsset(address(asset3), true);
        vm.stopPrank();

        uint256 initialAssetsCount = vault.getAssets().length;
        assertEq(vault.getAssets().length, initialAssetsCount, "Initial assets count should match");

        // Get index of the last asset
        address[] memory assets = vault.getAssets();
        uint256 lastAssetIndex = assets.length - 1;
        address lastAsset = assets[lastAssetIndex];

        // Store asset params before deletion
        IVault.AssetParams[] memory beforeStates = new IVault.AssetParams[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            beforeStates[i] = vault.getAsset(assets[i]);
        }

        // Delete the last asset
        vm.startPrank(ASSET_MANAGER);
        vault.deleteAsset(lastAssetIndex);
        vm.stopPrank();

        uint256 expectedAssetsCount = initialAssetsCount - 1;
        assertEq(vault.getAssets().length, expectedAssetsCount, "Assets count should decrease by 1 after deletion");

        // Verify the last asset is removed and the rest of the assets match the original array (except the last one)
        address[] memory updatedAssets = vault.getAssets();
        for (uint256 i = 0; i < updatedAssets.length; i++) {
            assertNotEq(updatedAssets[i], lastAsset, "Last asset should not be in the assets array anymore");
            assertEq(updatedAssets[i], assets[i], "Remaining assets should match the original array");

            // Verify active status, index and decimals remain unchanged for non-deleted assets
            IVault.AssetParams memory currentParams = vault.getAsset(updatedAssets[i]);
            assertEq(currentParams.active, beforeStates[i].active, "Asset active status should remain unchanged");
            assertEq(currentParams.index, beforeStates[i].index, "Asset index should remain unchanged");
            assertEq(currentParams.decimals, beforeStates[i].decimals, "Asset decimals should remain unchanged");
        }

        // Verify the asset is no longer active and its index is wiped out
        assertFalse(vault.getAsset(lastAsset).active, "Last asset should not be active anymore");
        assertEq(vault.getAsset(lastAsset).index, 0, "Last asset's index should be reset to 0");
    }

    function test_Vault_deleteAsset_notEmpty() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vault.addAsset(address(asset2), true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 8);

        deal(address(asset2), address(vault), 100);
        vm.startPrank(ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(IVault.AssetNotEmpty.selector, address(asset2)));
        vault.deleteAsset(7);
        vm.stopPrank();
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
        vault.setBuffer(address(0));

        assertEq(vault.buffer(), address(0));
    }

    function test_Vault_setBuffer_toggle() public {
        address originalBuffer = vault.buffer();

        // Set buffer to address(0)
        vm.prank(ADMIN);
        vault.setBuffer(address(0));
        assertEq(vault.buffer(), address(0), "Buffer should be set to zero address");

        // Set buffer back to previous/original buffer
        vm.prank(ADMIN);
        vault.setBuffer(originalBuffer);
        assertEq(vault.buffer(), originalBuffer, "Buffer should be set back to original value");
    }

    function test_Vault_pause_whenPaused() public {
        vm.prank(PAUSER);
        vault.pause();
        vm.prank(PAUSER);
        vm.expectRevert();
        vault.pause();
    }

    function test_Vault_unpause_notPaused() public {
        vm.prank(UNPAUSER);
        vm.expectRevert();
        vault.unpause();
    }

    function test_Vault_unpause_revertsWhenProviderNotSet() public {
        // Create a new vault without provider
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));
        newVault.initialize(address(this), "Test", "TST", 18, 0, false, false, 0);

        // Grant unpauser role
        newVault.grantRole(newVault.UNPAUSER_ROLE(), address(this));

        // Try to unpause without provider - should revert
        vm.expectRevert(IVault.ProviderNotSet.selector);
        newVault.unpause();
    }

    function test_Vault_unpause_succeedsWhenProviderSet() public {
        vm.prank(PAUSER);
        vault.pause();

        vm.prank(UNPAUSER);
        vault.unpause();

        assertFalse(vault.paused(), "Vault should be unpaused");
    }

    function test_Vault_pause_whenAlreadyPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        vm.expectRevert(IVault.Paused.selector);
        vm.prank(PAUSER);
        vault.pause();
    }

    function test_Vault_setAlwaysComputeTotalAssets_callsProcessAccountingWhenDisabling() public {
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        // Enable always compute
        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(true);
        assertTrue(vault.alwaysComputeTotalAssets());

        // Add some yield
        deal(address(weth), address(this), 0.1 ether);
        weth.transfer(address(vault), 0.1 ether);

        // Disable always compute - should call processAccounting
        uint256 totalAssetsBefore = vault.totalAssets();
        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(false);

        // Total assets should be updated after processAccounting
        assertFalse(vault.alwaysComputeTotalAssets());
        assertGe(vault.totalAssets(), totalAssetsBefore, "Total assets should be updated");
    }

    function test_Vault_setAlwaysComputeTotalAssets_emitsEvent() public {
        bool previous = vault.alwaysComputeTotalAssets();
        vm.expectEmit(true, false, false, false);
        emit IVault.SetAlwaysComputeTotalAssets(previous, true);

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(true);
    }

    function test_Vault_setAlwaysComputeTotalAssets_unauthorized() public {
        vm.expectRevert();
        vault.setAlwaysComputeTotalAssets(true);
    }

    function test_Vault_setProvider_emitsEvent() public {
        address oldProvider = vault.provider();
        address newProvider = address(0x123);

        vm.expectEmit(true, true, false, false);
        emit IVault.SetProvider(oldProvider, newProvider);

        vm.prank(PROVIDER_MANAGER);
        vault.setProvider(newProvider);

        assertEq(vault.provider(), newProvider, "Provider should be set");
    }

    function test_Vault_setProvider_unauthorized() public {
        vm.expectRevert();
        vault.setProvider(address(0x123));
    }

    function test_Vault_setBuffer_emitsEvent() public {
        address newBuffer = address(0x456);
        address oldBuffer = vault.buffer();

        vm.expectEmit(true, true, false, false);
        emit IVault.SetBuffer(oldBuffer, newBuffer);

        vm.prank(BUFFER_MANAGER);
        vault.setBuffer(newBuffer);
    }

    function test_Vault_setBuffer_unauthorized() public {
        vm.expectRevert();
        vault.setBuffer(address(0x456));
    }

    function test_Vault_addAsset_firstAssetWithDifferentDecimals() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // This is a duplicate initialization - the vault was already initialized in the proxy constructor
        newVault.initialize(address(this), "Test Vault", "TV", 18, 0, true, false, 0);

        // Create mock asset with 6 decimals
        MockERC20CustomDecimals sixDecimalAsset = new MockERC20CustomDecimals("Test", "TST", 6);

        // Grant asset manager role
        newVault.grantRole(newVault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);

        vm.startPrank(ASSET_MANAGER);

        // Should revert when trying to add 6 decimal asset as first asset
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidNativeAssetDecimals.selector, 6));
        newVault.addAsset(address(sixDecimalAsset), true);

        vm.stopPrank();
    }

    function test_Vault_addAsset_firstAssetWithDifferentDecimals_noNativeAsset() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // This is a duplicate initialization - the vault was already initialized in the proxy constructor
        newVault.initialize(address(this), "Test Vault", "TV", 18, 0, false, false, 0);

        // Create mock asset with 8 decimals
        MockERC20CustomDecimals eightDecimalAsset = new MockERC20CustomDecimals("Test", "TST", 8);

        // Grant asset manager role
        newVault.grantRole(newVault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);

        vm.startPrank(ASSET_MANAGER);

        // Should revert when trying to add 8 decimal asset as first asset when vault has 18 decimals
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAssetDecimals.selector, 8));
        newVault.addAsset(address(eightDecimalAsset), true);

        vm.stopPrank();
    }

    function test_Vault_With8Decimals_addAsset_with8Decimals() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // Initialize vault with 8 decimals
        newVault.initialize(address(this), "Test Vault", "TV", 8, 0, false, false, 0);

        // Create mock asset with 8 decimals
        MockERC20CustomDecimals eightDecimalAsset = new MockERC20CustomDecimals("Test", "TST", 8);

        // Grant asset manager role
        newVault.grantRole(newVault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);

        vm.startPrank(ASSET_MANAGER);

        // Should succeed when adding 8 decimal asset to vault with 8 decimals
        newVault.addAsset(address(eightDecimalAsset), true);

        // Verify asset was added correctly
        IVault.AssetParams memory assetParams = newVault.getAsset(address(eightDecimalAsset));
        assertEq(assetParams.active, true);
        assertEq(assetParams.decimals, 8);
        assertEq(assetParams.index, 0);

        vm.stopPrank();
    }

    function test_Vault_WithDefaultAssetIndex1_addAsset_with8Decimals() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // Initialize vault with 8 decimals and default asset index of 1
        newVault.initialize(address(this), "Test Vault", "TV", 8, 0, false, false, 1);

        // Create mock assets with 8 decimals
        MockERC20CustomDecimals eightDecimalAsset1 = new MockERC20CustomDecimals("Test1", "TST1", 8);
        MockERC20CustomDecimals eightDecimalAsset2 = new MockERC20CustomDecimals("Test2", "TST2", 8);

        // Grant asset manager role
        newVault.grantRole(newVault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);

        vm.startPrank(ASSET_MANAGER);

        // Add first asset
        newVault.addAsset(address(eightDecimalAsset1), true);

        // Add second asset (should be the default asset since default index is 1)
        newVault.addAsset(address(eightDecimalAsset2), true);

        // Verify assets were added correctly
        IVault.AssetParams memory asset1Params = newVault.getAsset(address(eightDecimalAsset1));
        assertEq(asset1Params.active, true);
        assertEq(asset1Params.decimals, 8);
        assertEq(asset1Params.index, 0);

        IVault.AssetParams memory asset2Params = newVault.getAsset(address(eightDecimalAsset2));
        assertEq(asset2Params.active, true);
        assertEq(asset2Params.decimals, 8);
        assertEq(asset2Params.index, 1);

        // Verify default asset index is 1
        assertEq(newVault.defaultAssetIndex(), 1);

        vm.stopPrank();
    }
}
