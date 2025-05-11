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

        // Verify roles
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Admin), "Admin role not granted");
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
}
