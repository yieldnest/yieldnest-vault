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

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1_000 * 10 ** 18;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Deploy mock asset
        asset = new MockERC20("Mock Token", "MOCK");
        asset2 = new MockERC20("Mock Token 2", "MOCK2");

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

    function test_Vault_deleteAsset_defaultAsset() public {
        vm.prank(ASSET_MANAGER);
        vm.expectRevert(IVault.DefaultAsset.selector);
        vault.deleteAsset(0);
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

        assertEq(vault.getAssets().length, 7);

        vm.startPrank(ASSET_MANAGER);
        vault.deleteAsset(1);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 6);
    }

    function test_Vault_deleteAsset_notEmpty() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);
        vault.addAsset(address(asset2), true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 7);

        deal(address(asset2), address(vault), 100);
        vm.startPrank(ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(IVault.AssetNotEmpty.selector, address(asset2)));
        vault.deleteAsset(6);
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
        vm.expectRevert();
        vault.setBuffer(address(0));
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

    function test_Vault_addAsset_firstAssetWithDifferentDecimals() public {
        // Deploy implementation and proxy
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            abi.encodeWithSelector(
                Vault.initialize.selector,
                address(this),
                "Test Vault",
                "TV",
                18,
                0, // baseWithdrawalFee
                true, // countNativeAsset
                false // alwaysComputeTotalAssets
            )
        );
        Vault newVault = Vault(payable(address(proxy)));

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
}
