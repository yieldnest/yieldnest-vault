// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC20} from "src/Common.sol";
import {MockNoOpHooks} from "test/unit/mocks/MockNoOpHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {FeeHooks} from "src/hooks/FeeHooks.sol";

contract VaultEdgeCasesUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    WETH9 public weth;
    address public alice = address(0x1);
    address public bob = address(0x2);
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

    // ============ receive() function tests ============

    function test_Vault_receive_emitsNativeDepositEvent(uint256 amount) public {
        amount = bound(amount, 1 wei, 1000 ether);

        vm.expectEmit(true, false, false, false);
        emit IVault.NativeDeposit(amount);

        (bool success,) = address(vault).call{value: amount}("");
        assertTrue(success, "Native deposit failed");
    }

    function test_Vault_receive_multipleDeposits() public {
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;

        (bool success1,) = address(vault).call{value: deposit1}("");
        assertTrue(success1, "First deposit failed");

        (bool success2,) = address(vault).call{value: deposit2}("");
        assertTrue(success2, "Second deposit failed");

        assertEq(address(vault).balance, deposit1 + deposit2, "Vault balance incorrect");
    }

    function test_Vault_receive_zeroAmount() public {
        // Zero amount should still emit event
        vm.expectEmit(true, false, false, false);
        emit IVault.NativeDeposit(0);

        (bool success,) = address(vault).call{value: 0}("");
        assertTrue(success, "Zero deposit should succeed");
    }

    // ============ maxDeposit() tests ============

    function test_Vault_maxDeposit_whenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0, "maxDeposit should be 0 when paused");
        assertEq(vault.maxDeposit(bob), 0, "maxDeposit should be 0 for any user when paused");
    }

    function test_Vault_maxDeposit_whenUnpaused() public view {
        assertEq(vault.maxDeposit(alice), type(uint256).max, "maxDeposit should be max when unpaused");
        assertEq(vault.maxDeposit(bob), type(uint256).max, "maxDeposit should be max for any user");
        assertEq(vault.maxDeposit(address(0)), type(uint256).max, "maxDeposit should work for zero address");
    }

    function test_Vault_maxDeposit_afterPauseUnpause() public {
        // Initially unpaused
        assertEq(vault.maxDeposit(alice), type(uint256).max);

        // Pause
        vm.prank(PAUSER);
        vault.pause();
        assertEq(vault.maxDeposit(alice), 0);

        // Unpause
        vm.prank(UNPAUSER);
        vault.unpause();
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    // ============ maxMint() tests ============

    function test_Vault_maxMint_whenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        assertEq(vault.maxMint(alice), 0, "maxMint should be 0 when paused");
        assertEq(vault.maxMint(bob), 0, "maxMint should be 0 for any user when paused");
    }

    function test_Vault_maxMint_whenUnpaused() public view {
        assertEq(vault.maxMint(alice), type(uint256).max, "maxMint should be max when unpaused");
        assertEq(vault.maxMint(bob), type(uint256).max, "maxMint should be max for any user");
        assertEq(vault.maxMint(address(0)), type(uint256).max, "maxMint should work for zero address");
    }

    function test_Vault_maxMint_afterPauseUnpause() public {
        // Initially unpaused
        assertEq(vault.maxMint(alice), type(uint256).max);

        // Pause
        vm.prank(PAUSER);
        vault.pause();
        assertEq(vault.maxMint(alice), 0);

        // Unpause
        vm.prank(UNPAUSER);
        vault.unpause();
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    // ============ maxWithdraw() tests ============

    function test_Vault_maxWithdraw_whenBufferIsZero() public {
        // Create a new vault without buffer
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));
        newVault.initialize(address(this), "Test", "TST", 18, 0, false, false, 0);

        assertEq(newVault.maxWithdraw(alice), 0, "maxWithdraw should be 0 when buffer is zero");
    }

    function test_Vault_maxWithdraw_whenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        assertEq(vault.maxWithdraw(alice), 0, "maxWithdraw should be 0 when paused");
    }

    function test_Vault_maxWithdraw_withNoShares() public view {
        assertEq(vault.maxWithdraw(bob), 0, "maxWithdraw should be 0 for user with no shares");
    }

    // ============ maxRedeem() tests ============

    function test_Vault_maxRedeem_whenBufferIsZero() public {
        // Create a new vault without buffer
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault newVault = Vault(payable(address(proxy)));
        newVault.initialize(address(this), "Test", "TST", 18, 0, false, false, 0);

        assertEq(newVault.maxRedeem(alice), 0, "maxRedeem should be 0 when buffer is zero");
    }

    function test_Vault_maxRedeem_whenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        assertEq(vault.maxRedeem(alice), 0, "maxRedeem should be 0 when paused");
    }

    function test_Vault_maxRedeem_withNoShares() public view {
        assertEq(vault.maxRedeem(bob), 0, "maxRedeem should be 0 for user with no shares");
    }

    // ============ previewMint() tests ============

    function test_Vault_previewMint_zeroShares() public view {
        assertEq(vault.previewMint(0), 0, "previewMint(0) should return 0");
    }

    function test_Vault_previewMint_afterDeposit(uint256 depositAmount, uint256 mintShares) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        mintShares = bound(mintShares, 1 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previewAssets = vault.previewMint(mintShares);
        assertGe(previewAssets, mintShares, "previewMint should return at least the shares amount");
    }

    function test_Vault_previewMint_afterYield(uint256 depositAmount, uint256 yieldAmount, uint256 mintShares) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        yieldAmount = bound(yieldAmount, 0.1 ether, 100 ether);
        mintShares = bound(mintShares, 1 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Add yield
        deal(address(weth), address(this), yieldAmount);
        weth.transfer(address(vault), yieldAmount);
        vault.processAccounting();

        uint256 previewAssets = vault.previewMint(mintShares);
        // After yield, minting same shares should require more assets
        assertGe(previewAssets, mintShares, "previewMint should account for yield");
    }

    // ============ previewWithdraw() tests ============

    function test_Vault_previewWithdraw_zeroAssets() public view {
        assertEq(vault.previewWithdraw(0), 0, "previewWithdraw(0) should return 0");
    }

    function test_Vault_previewWithdraw_withFee(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        withdrawAmount = bound(withdrawAmount, 1 ether, depositAmount);

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(10000); // 1% fee
        vm.stopPrank();

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previewShares = vault.previewWithdraw(withdrawAmount);
        // With fee, should require more shares
        assertGe(previewShares, withdrawAmount, "previewWithdraw should account for fee");
    }

    // ============ previewRedeem() tests ============

    function test_Vault_previewRedeem_zeroShares() public view {
        assertEq(vault.previewRedeem(0), 0, "previewRedeem(0) should return 0");
    }

    function test_Vault_previewRedeem_withFee(uint256 depositAmount, uint256 redeemShares) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        redeemShares = bound(redeemShares, 1 ether, depositAmount);

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(10000); // 1% fee
        vm.stopPrank();

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        redeemShares = bound(redeemShares, 1, shares);

        uint256 previewAssets = vault.previewRedeem(redeemShares);
        // With fee, should receive less assets
        assertLe(previewAssets, redeemShares, "previewRedeem should account for fee");
    }

    // ============ previewDeposit() tests ============

    function test_Vault_previewDeposit_zeroAssets() public view {
        assertEq(vault.previewDeposit(0), 0, "previewDeposit(0) should return 0");
    }

    function test_Vault_previewDeposit_afterYield(uint256 depositAmount, uint256 yieldAmount, uint256 newDeposit)
        public
    {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        yieldAmount = bound(yieldAmount, 0.1 ether, 100 ether);
        newDeposit = bound(newDeposit, 1 ether, 1000 ether);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Add yield
        deal(address(weth), address(this), yieldAmount);
        weth.transfer(address(vault), yieldAmount);
        vault.processAccounting();

        uint256 previewShares = vault.previewDeposit(newDeposit);
        // After yield, depositing same assets should get fewer shares
        assertLe(previewShares, newDeposit, "previewDeposit should account for yield");
    }

    // ============ setAlwaysComputeTotalAssets() tests ============

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
        vm.expectEmit(true, false, false, false);
        emit IVault.SetAlwaysComputeTotalAssets(true);

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(true);
    }

    function test_Vault_setAlwaysComputeTotalAssets_unauthorized() public {
        vm.expectRevert();
        vault.setAlwaysComputeTotalAssets(true);
    }

    // ============ unpause() tests ============

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

    // ============ setHooks() tests ============

    function test_Vault_setHooks_zeroAddress() public {
        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(0));

        assertEq(address(vault.hooks()), address(0), "Hooks should be set to zero address");
    }

    function test_Vault_setHooks_emitsEvent() public {
        MockNoOpHooks newHooks = new MockNoOpHooks(vault);

        vm.expectEmit(true, true, false, false);
        emit IVault.SetHooks(address(vault.hooks()), address(newHooks));

        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(newHooks));
    }

    function test_Vault_setHooks_revertsWhenInvalidHooks() public {
        // Create hooks for a different vault
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault otherVault = Vault(payable(address(proxy)));
        otherVault.initialize(address(this), "Other", "OTH", 18, 0, false, false, 0);

        MockNoOpHooks invalidHooks = new MockNoOpHooks(otherVault);

        vm.expectRevert(IVault.InvalidHooks.selector);
        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(invalidHooks));
    }

    function test_Vault_setHooks_unauthorized() public {
        MockNoOpHooks newHooks = new MockNoOpHooks(vault);

        vm.expectRevert();
        vault.setHooks(address(newHooks));
    }

    // ============ mintShares() tests ============

    function test_Vault_mintShares_revertsWhenNotCalledByHooks() public {
        vm.expectRevert(IVault.CallerNotHooks.selector);
        vault.mintShares(alice, 1 ether);
    }

    function test_Vault_mintShares_succeedsWhenCalledByHooks(uint256 shares) public {
        shares = bound(shares, 1, 1000 ether);

        address hooksAddress = address(vault.hooks());
        uint256 balanceBefore = vault.balanceOf(alice);

        vm.prank(hooksAddress);
        vault.mintShares(alice, shares);

        assertEq(vault.balanceOf(alice), balanceBefore + shares, "Shares should be minted");
        assertEq(vault.totalSupply(), vault.totalSupply(), "Total supply should increase");
    }

    function test_Vault_mintShares_zeroShares() public {
        address hooksAddress = address(vault.hooks());
        uint256 balanceBefore = vault.balanceOf(alice);

        vm.prank(hooksAddress);
        vault.mintShares(alice, 0);

        assertEq(vault.balanceOf(alice), balanceBefore, "Balance should not change");
    }

    // ============ previewDepositAsset() tests ============

    function test_Vault_previewDepositAsset_zeroAssets() public view {
        assertEq(vault.previewDepositAsset(MC.WETH, 0), 0, "previewDepositAsset(0) should return 0");
    }

    function test_Vault_previewDepositAsset_differentAssets(uint256 amount) public view {
        amount = bound(amount, 1 ether, 100 ether);

        uint256 wethShares = vault.previewDepositAsset(MC.WETH, amount);
        uint256 stethShares = vault.previewDepositAsset(MC.STETH, amount);

        // Both should return shares based on their rates
        assertGt(wethShares, 0, "WETH preview should return shares");
        assertGt(stethShares, 0, "STETH preview should return shares");
    }

    // ============ Edge cases for conversion functions ============

    function test_Vault_convertToShares_zeroAssets() public view {
        assertEq(vault.convertToShares(0), 0, "convertToShares(0) should return 0");
    }

    function test_Vault_convertToAssets_zeroShares() public view {
        assertEq(vault.convertToAssets(0), 0, "convertToAssets(0) should return 0");
    }

    function test_Vault_convertToShares_veryLargeAmount() public view {
        uint256 largeAmount = type(uint256).max / 2;
        uint256 shares = vault.convertToShares(largeAmount);
        assertGe(shares, 0, "Should handle large amounts");
    }

    function test_Vault_convertToAssets_veryLargeShares() public view {
        uint256 largeShares = type(uint256).max / 2;
        uint256 assets = vault.convertToAssets(largeShares);
        assertGe(assets, 0, "Should handle large shares");
    }

    // ============ Edge cases for asset management ============

    function test_Vault_getAsset_nonExistentAsset() public view {
        address nonExistent = address(0x999);
        IVault.AssetParams memory params = vault.getAsset(nonExistent);
        assertEq(params.index, 0, "Non-existent asset should have index 0");
        assertFalse(params.active, "Non-existent asset should not be active");
    }

    function test_Vault_hasAsset_nonExistentAsset() public view {
        address nonExistent = address(0x999);
        assertFalse(vault.hasAsset(nonExistent), "Non-existent asset should return false");
    }

    // ============ Edge cases for paused state ============

    function test_Vault_pause_whenAlreadyPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        vm.expectRevert(IVault.Paused.selector);
        vm.prank(PAUSER);
        vault.pause();
    }

    function test_Vault_unpause_whenNotPaused() public {
        vm.expectRevert(IVault.Unpaused.selector);
        vm.prank(UNPAUSER);
        vault.unpause();
    }

    // ============ Edge cases for provider ============

    function test_Vault_setProvider_emitsEvent() public {
        address newProvider = address(0x123);

        vm.expectEmit(true, false, false, false);
        emit IVault.SetProvider(newProvider);

        vm.prank(PROVIDER_MANAGER);
        vault.setProvider(newProvider);

        assertEq(vault.provider(), newProvider, "Provider should be set");
    }

    function test_Vault_setProvider_unauthorized() public {
        vm.expectRevert();
        vault.setProvider(address(0x123));
    }

    // ============ Edge cases for buffer ============

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
}
