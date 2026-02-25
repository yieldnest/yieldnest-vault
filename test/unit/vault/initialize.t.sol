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
import {Initializable} from "src/Common.sol";

contract VaultInitializeUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    WETH9 public weth;
    MockERC20 public asset;
    MockERC20 public asset2;
    MockERC20 public asset3;

    function setUp() public {
        // Deploy implementation and proxy without initializing
        Vault vaultImplementation = new Vault();
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), address(this), "");
        vault = Vault(payable(address(vaultProxy)));

        // Deploy WETH for testing
        weth = new WETH9();
        asset = new MockERC20("Mock Token", "MOCK");
        asset2 = new MockERC20("Mock Token 2", "MOCK2");
        asset3 = new MockERC20("Mock Token 3", "MOCK3");
    }

    function test_Vault_initialize(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 defaultAssetIndex,
        bool alwaysComputeTotalAssets,
        uint64 fee,
        bool countNativeAsset
    ) public {
        // Bound the inputs to reasonable values
        vm.assume(bytes(name).length > 0 && bytes(name).length <= 32);
        vm.assume(bytes(symbol).length > 0 && bytes(symbol).length <= 8);
        decimals = uint8(bound(decimals, 1, 36)); // Bound decimals between 1 and 36
        defaultAssetIndex = bound(defaultAssetIndex, 0, 1); // 0 or 1 since we'll only have 2 assets max
        fee = uint64(bound(fee, 0, 10000)); // Fee is typically expressed in basis points (0-10000)

        address Admin = address(0xABCD);

        // Initialize the vault
        vault.initialize(
            Admin, name, symbol, decimals, fee, countNativeAsset, alwaysComputeTotalAssets, defaultAssetIndex
        );

        // Verify initialization parameters
        assertEq(vault.name(), name, "Name mismatch");
        assertEq(vault.symbol(), symbol, "Symbol mismatch");
        assertEq(vault.decimals(), decimals, "Decimals mismatch");
        assertEq(vault.baseWithdrawalFee(), fee, "Fee mismatch");
        assertEq(vault.defaultAssetIndex(), defaultAssetIndex, "Default asset index mismatch");
        assertEq(vault.alwaysComputeTotalAssets(), alwaysComputeTotalAssets, "Always compute total assets mismatch");
        assertEq(vault.countNativeAsset(), countNativeAsset, "countNativeAsset mismatch");

        // Verify roles
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Admin), "Admin role not granted");

        // The vault should start paused
        assertTrue(vault.paused(), "Vault should be paused after initialization");
    }

    function test_Vault_initialize_withAssets(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 defaultAssetIndex,
        bool alwaysComputeTotalAssets,
        uint64 fee,
        bool countNativeAsset
    ) public {
        // Bound the inputs to reasonable values
        vm.assume(bytes(name).length > 0 && bytes(name).length <= 32);
        vm.assume(bytes(symbol).length > 0 && bytes(symbol).length <= 8);
        decimals = uint8(bound(decimals, 1, 36)); // Bound decimals between 1 and 36
        defaultAssetIndex = bound(defaultAssetIndex, 0, 1); // 0 or 1 since we'll only have 2 assets max
        fee = uint64(bound(fee, 0, 10000)); // Fee is typically expressed in basis points (0-10000)

        if (countNativeAsset) {
            decimals = 18;
        }

        address Admin = address(0xABCD);

        // Initialize the vault
        vault.initialize(
            Admin, name, symbol, decimals, fee, countNativeAsset, alwaysComputeTotalAssets, defaultAssetIndex
        );

        // Reinitialize should revert
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(
            Admin, name, symbol, decimals, fee, countNativeAsset, alwaysComputeTotalAssets, defaultAssetIndex
        );

        MockERC20CustomDecimals asset1 = new MockERC20CustomDecimals("ASSET1", "ASSET1", decimals);
        MockERC20CustomDecimals asset2 = new MockERC20CustomDecimals("ASSET2", "ASSET2", decimals);
        {
            vm.startPrank(Admin);
            vault.grantRole(vault.ASSET_MANAGER_ROLE(), Admin);

            vault.addAsset(address(asset1), true);
            vault.addAsset(address(asset2), true);
            vm.stopPrank();
        }

        if (defaultAssetIndex == 0) {
            assertEq(vault.asset(), address(asset1), "Asset should be WETH");
        } else {
            assertEq(vault.asset(), address(asset2), "Asset should be asset");
        }
    }

    function test_Vault_initialize_revertWhenAlreadyInitialized() public {
        // Initialize the vault first time
        vault.initialize(address(this), "Test Vault", "TV", 18, 0, false, true, 0);

        // Try to initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(address(this), "Test Vault 2", "TV2", 18, 0, false, true, 0);
    }

    function test_Vault_initialize_revertWithInvalidDefaultAssetIndex(uint256 defaultAssetIndex) public {
        vm.assume(defaultAssetIndex > 1 && defaultAssetIndex < 1000);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidDefaultAssetIndex.selector, defaultAssetIndex));
        vault.initialize(address(0), "Test Vault", "TV", 18, 0, false, true, defaultAssetIndex);
    }

    function test_Vault_initialize_revertWithInvalidFee(uint64 fee) public {
        // Assume fee is greater than the maximum allowed (FeeMath.BASIS_POINT_SCALE which is 10000)
        vm.assume(fee > 1e8 && fee < 1e10);

        vm.expectRevert(abi.encodeWithSelector(IVault.ExceedsMaxBasisPoints.selector, fee));
        vault.initialize(address(this), "Test Vault", "TV", 18, fee, false, true, 0);
    }

    function test_Vault_initialize_revertWithInvalidDecimals() public {
        uint8 invalidDecimals = 0;

        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidDecimals.selector));
        vault.initialize(address(this), "Test Vault", "TV", invalidDecimals, 0, false, true, 0);
    }

    function test_Vault_initialize_doesNotRevertWithZeroAdmin() public {
        vault.initialize(address(0), "Test Vault", "TV", 18, 0, false, true, 0);
    }

    function test_Vault_initialize_No_RevertInvalidNativeAssetDecimals() public {
        // Case: countNativeAsset is true, decimals != 18
        uint8 invalidNativeDecimals = 10;
        // Use 0 for defaultAssetIndex, which is allowed
        vault.initialize(address(this), "Test Vault", "TV", invalidNativeDecimals, 0, true, true, 0);
    }

    function test_Vault_initialize_revertWhenAddFirstAssetInvalidNativeAssetDecimals() public {
        // Initialize the vault with countNativeAsset = true and decimals not 18
        uint8 invalidNativeDecimals = 10;
        vault.initialize(address(this), "Test Vault", "TV", invalidNativeDecimals, 0, true, true, 0);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));

        // Deploy a MockERC20 with wrong decimals for base asset (first asset)
        MockERC20CustomDecimals badNativeAsset = new MockERC20CustomDecimals("BadNative", "BADN", invalidNativeDecimals);

        // Adding the first asset should revert with InvalidNativeAssetDecimals when countNativeAsset is true and decimals != 18
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidNativeAssetDecimals.selector, invalidNativeDecimals));
        vault.addAsset(address(badNativeAsset), true);
    }

    function test_Vault_initialize_validWithNativeAssetDecimals18() public {
        // Should not revert if decimals is 18 and countNativeAsset is true
        vault.initialize(address(this), "Test Vault", "TV", 18, 0, true, true, 0);
    }

    function test_Vault_initialize_validWithDefaultAssetIndex1() public {
        // Should not revert if defaultAssetIndex is 1 (allowed)
        vault.initialize(address(this), "Test Vault", "TV", 18, 0, false, true, 1);
    }

    function test_Vault_initialize_revertWithAssetDecimalsHigherThanBaseAsset() public {
        address admin = address(0xABCD);
        vault.initialize(admin, "Test Vault", "TV", 18, 0, false, true, 0);

        vm.startPrank(admin);

        MockERC20CustomDecimals baseAsset = new MockERC20CustomDecimals("BaseAsset", "BA", 18);
        // Add base asset (first asset), decimals = 18
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.addAsset(address(baseAsset), true);
        vm.stopPrank();

        // Try to add asset with decimals > base decimals using a real ERC20 mock
        uint8 higherDecimals = 20;
        MockERC20CustomDecimals highDecAsset = new MockERC20CustomDecimals("HighDecAsset", "HDA", higherDecimals);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidAssetDecimals.selector, higherDecimals));
        vault.addAsset(address(highDecAsset), true);
        vm.stopPrank();
    }

    function test_Vault_initialize_revertWithDuplicateAsset() public {
        vault.initialize(address(this), "Test Vault", "TV", 18, 0, false, true, 0);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));

        // Use a mock asset
        MockERC20 mockAsset = new MockERC20("Mock Token", "MOCK");

        // Add base asset
        vault.addAsset(address(mockAsset), true);

        // Try to add the same asset again (should revert as duplicate)
        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(mockAsset)));
        vault.addAsset(address(mockAsset), true);
    }

    function test_Vault_initialize_revertWithZeroAddressAsset() public {
        vault.initialize(address(this), "Test Vault", "TV", 18, 0, false, true, 0);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));

        // Try to add asset with zero address; fails on the decimals call
        vm.expectRevert();
        vault.addAsset(address(0), true);
    }
}
