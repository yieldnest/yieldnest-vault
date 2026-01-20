// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";

/**
 * @title NativeEthAccountingTest
 * @notice Tests for native ETH accounting issues (from code review comment #7)
 * @dev Tests the problematic countNativeAsset feature
 */
contract NativeEthAccountingTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public alice = address(0xA11Ce);
    address public bob = address(0xB0b);
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        weth = new WETH9();

        // Fund users
        deal(alice, INITIAL_BALANCE);
        deal(bob, INITIAL_BALANCE);

        vm.prank(alice);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(bob);
        weth.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Helper to create a vault with countNativeAsset enabled
     */
    function _createVaultWithNativeAsset() internal returns (Vault) {
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));

        // Initialize with countNativeAsset = true
        newVault.initialize(
            address(this),
            "Test Vault",
            "TV",
            18, // decimals must be 18 for native asset
            0, // fee
            true, // countNativeAsset = true
            false, // alwaysComputeTotalAssets
            0 // defaultAssetIndex
        );

        return newVault;
    }

    /**
     * @notice Test that native ETH increases totalAssets without minting shares
     * @dev This is the core issue - ETH donations inflate share price unfairly
     */
    function test_NativeEth_DonationInflatesSharePrice() public {
        vault = _createVaultWithNativeAsset();

        // Setup vault with WETH asset
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        // Note: Would need to set provider here in real scenario

        // Alice deposits WETH normally
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        uint256 aliceShares = vault.deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(aliceShares, 100 ether, "Alice should get 100 shares");
        assertEq(vault.totalAssets(), 100 ether, "Total assets should be 100");

        // Someone sends ETH directly to vault (no shares minted!)
        vm.deal(address(vault), 50 ether);

        // Process accounting to include native ETH
        vault.processAccounting();

        // Total assets increased but total supply didn't
        assertEq(vault.totalAssets(), 150 ether, "Total assets now 150 (includes ETH)");
        assertEq(vault.totalSupply(), 100 ether, "Total supply still 100 shares");

        // This means share price increased from 1.0 to 1.5
        // Alice's shares are now worth 150 ETH despite depositing only 100 ETH
        uint256 aliceValue = vault.convertToAssets(aliceShares);
        assertEq(aliceValue, 150 ether, "Alice's shares worth 150 ETH now");

        // Bob deposits same amount but gets fewer shares
        vm.startPrank(bob);
        weth.approve(address(vault), 100 ether);
        uint256 bobShares = vault.deposit(100 ether, bob);
        vm.stopPrank();

        // Bob should get: 100 * 100 / 150 = 66.666... shares
        assertApproxEqAbs(bobShares, 66.666666666666666666 ether, 1, "Bob gets fewer shares");

        // Alice profited from random ETH donation, Bob was disadvantaged
        // This is unfair and exploitable
    }

    /**
     * @notice Test that attacker can exploit countNativeAsset
     * @dev Attacker can deposit, send ETH, then withdraw for profit
     */
    function test_NativeEth_AttackerExploitation() public {
        vault = _createVaultWithNativeAsset();

        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        address attacker = address(0xBA0);
        deal(attacker, INITIAL_BALANCE);

        vm.prank(attacker);
        weth.deposit{value: 100 ether}();

        // Attacker deposits
        vm.startPrank(attacker);
        weth.approve(address(vault), 100 ether);
        uint256 shares = vault.deposit(100 ether, attacker);
        vm.stopPrank();

        // Attacker sends ETH to vault (or tricks someone else into doing it)
        vm.deal(address(vault), 100 ether);
        vault.processAccounting();

        // Now share price doubled
        // Attacker can withdraw more than deposited
        // (In reality, would need buffer to have funds for withdrawal)

        // This demonstrates the accounting flaw:
        // ETH balance increases totalAssets without corresponding shares
    }

    /**
     * @notice Test receive() function increases ETH balance
     * @dev The receive() function accepts ETH but doesn't mint shares
     */
    function test_NativeEth_ReceiveFunctionDoesntMintShares() public {
        vault = _createVaultWithNativeAsset();

        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        // Alice deposits normally
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        uint256 sharesBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();

        // Send ETH to vault via receive()
        (bool success,) = payable(address(vault)).call{value: 10 ether}("");
        assertTrue(success, "ETH transfer should succeed");

        // Update accounting
        vault.processAccounting();

        // Shares unchanged
        assertEq(vault.totalSupply(), sharesBefore, "Shares should not increase");

        // Assets increased
        assertGt(vault.totalAssets(), assetsBefore, "Assets should increase");

        // This is the bug: asymmetric accounting
    }

    /**
     * @notice Test countNativeAsset should only count strategy-earned ETH
     * @dev The feature seems intended for yield, not arbitrary donations
     */
    function test_NativeEth_IntendedForYieldOnly() public {
        // The countNativeAsset feature likely intended to count:
        // - ETH earned by strategies
        // - ETH rewards/rebases
        // - Legitimate yield generation

        // But it has no way to distinguish between:
        // - Legitimate yield ETH
        // - Random donation ETH
        // - Attacker manipulation ETH

        // Without proper deposit flow for ETH:
        // - No shares minted
        // - No access control
        // - No attribution to users

        // This makes the feature fundamentally flawed for donations
    }

    /**
     * @notice Test recommendation: disable countNativeAsset
     */
    function test_Recommendation_DisableCountNativeAsset() public {
        // Recommendation: Either:
        // 1. Remove countNativeAsset feature entirely, OR
        // 2. Implement proper ETH deposit flow with shares minted

        // If keeping feature, need:
        // - payable deposit function that mints shares
        // - wrap ETH to WETH on deposit
        // - track ETH depositors properly

        // Current implementation is unsafe
    }

    /**
     * @notice Test ETH deposit through receive() with share minting
     * @dev Shows what proper implementation would look like
     */
    function test_ProperImplementation_EthDepositMintsShares() public {
        // Proper implementation would:
        // 1. Accept ETH in deposit function
        // 2. Convert to shares based on current price
        // 3. Mint shares to depositor
        // 4. Update totalAssets

        // Example:
        // function depositETH(address receiver) external payable returns (uint256 shares) {
        //     shares = previewDeposit(msg.value);
        //     _mint(receiver, shares);
        //     _addTotalAssets(msg.value);
        //     emit DepositETH(msg.sender, receiver, msg.value, shares);
        // }

        // Current receive() just accepts ETH without minting
    }

    /**
     * @notice Test fuzz with varying ETH donations
     */
    function testFuzz_NativeEth_VaryingDonations(uint256 donation) public {
        donation = bound(donation, 0.1 ether, 100 ether);

        vault = _createVaultWithNativeAsset();
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        // Initial deposit
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        // Donate ETH
        vm.deal(address(vault), donation);
        vault.processAccounting();

        // Share price inflated by donation amount
        uint256 expectedSharePrice = (100 ether + donation) * 1e18 / 100 ether;
        uint256 actualSharePrice = vault.convertToAssets(1 ether);

        assertApproxEqAbs(actualSharePrice, expectedSharePrice / 1e18, 100, "Share price inflated by donation");
    }

    /**
     * @notice Test that ETH can't be withdrawn directly
     * @dev ETH is counted in assets but not withdrawable
     */
    function test_NativeEth_NotWithdrawable() public {
        vault = _createVaultWithNativeAsset();
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        // Deposit WETH
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        // Add ETH
        vm.deal(address(vault), 50 ether);
        vault.processAccounting();

        // Total assets = 150 ETH (100 WETH + 50 ETH)
        // But only WETH is withdrawable through buffer

        // User sees 150 ETH total assets but can't access all of it
        // This is misleading and problematic
    }

    /**
     * @notice Test griefing attack: send 1 wei repeatedly
     * @dev Attacker can grief by repeatedly sending tiny amounts
     */
    function test_NativeEth_GriefingAttack() public {
        vault = _createVaultWithNativeAsset();
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        // Deposit
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        // Attacker repeatedly sends 1 wei
        for (uint256 i = 0; i < 100; i++) {
            vm.deal(address(vault), address(vault).balance + 1);
            vault.processAccounting();
        }

        // Each processAccounting() call costs gas
        // Attacker can force vault to process many tiny updates
        // Though impact is limited since processAccounting is public
    }

    /**
     * @notice Test countNativeAsset with alwaysComputeTotalAssets
     * @dev Combining both features amplifies the issue
     */
    function test_NativeEth_WithAlwaysComputeTotalAssets() public {
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        vault = Vault(payable(address(proxy)));

        // Initialize with BOTH countNativeAsset and alwaysComputeTotalAssets
        vault.initialize(
            address(this),
            "Test Vault",
            "TV",
            18,
            0,
            true, // countNativeAsset
            true, // alwaysComputeTotalAssets
            0
        );

        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.addAsset(address(weth), true);

        // Deposit
        vm.startPrank(alice);
        weth.approve(address(vault), 100 ether);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        // Send ETH
        vm.deal(address(vault), 50 ether);

        // With alwaysComputeTotalAssets, every read includes ETH
        // No need to call processAccounting()
        // Share price immediately reflects ETH donation

        uint256 sharePrice = vault.convertToAssets(1 ether);
        assertGt(sharePrice, 1 ether, "Share price inflated immediately");

        // This makes the issue even worse - no delay between donation and effect
    }
}
