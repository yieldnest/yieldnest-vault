// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, TransparentUpgradeableProxy, IERC4626, Math} from "src/Common.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";

contract VaultMintTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    IProvider public provider;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    // ─────────────────────────────────────────────────────────────────────
    // BASIC MINT FUNCTIONALITY
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mint a fixed amount of shares and verify all state transitions
    function test_mint_fixedAmount_stateTransitions() public {
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialConvertToAssets = vault.convertToAssets(1e18);
        uint256 initialConvertToShares = vault.convertToShares(1e6);

        uint256 sharesToMint = 1000e18;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Shares minted exactly
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice should receive exact shares requested");

        // Total supply increased by minted shares
        assertEq(
            vault.totalSupply(), initialTotalSupply + sharesToMint, "Total supply should increase by shares minted"
        );

        // Total assets increased by assets consumed
        assertEq(vault.totalAssets(), initialTotalAssets + assetsUsed, "Total assets should increase by assets used");

        // Assets used should match or exceed previewMint (ERC4626: mint must not require more than previewMint)
        assertLe(assetsUsed, requiredAssets, "Assets used must not exceed previewMint");

        // Exchange rate should remain stable (no dilution)
        assertEq(
            vault.convertToAssets(1e18),
            initialConvertToAssets,
            "convertToAssets rate should remain unchanged after mint"
        );
        assertApproxEqRel(
            vault.convertToShares(1e6),
            initialConvertToShares,
            1e12,
            "convertToShares rate should remain roughly unchanged after mint"
        );
    }

    /// @notice Mint to a different receiver than the caller
    function test_mint_toReceiver() public {
        uint256 sharesToMint = 500e18;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        vault.mint(sharesToMint, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(bob), sharesToMint, "Bob should receive the minted shares");
        assertEq(vault.balanceOf(alice), 0, "Alice should have zero shares (she paid, not received)");
    }

    /// @notice Verify previewMint returns correct value and actual mint does not exceed it
    function test_mint_previewMint_accuracy() public {
        uint256 sharesToMint = 2500e18;
        uint256 preview = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, preview);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), preview);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // ERC4626 spec: mint MUST NOT require more assets than previewMint
        assertLe(assetsUsed, preview, "Mint must not require more assets than previewMint returned");

        // previewMint rounds up (Ceil), so assetsUsed should equal preview
        assertEq(assetsUsed, preview, "Assets used should exactly match previewMint (both round Ceil)");
    }

    // ─────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Fuzz: mint random amount of shares, verify invariants
    function test_mint_fuzz_invariants(uint256 sharesToMint) public {
        // Bound: minimum 1 share (1e18), maximum 10M shares to keep within USDC supply limits
        sharesToMint = bound(sharesToMint, 1e18, 10_000_000e18);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Invariant 1: shares minted exactly
        assertEq(vault.balanceOf(alice), sharesToMint, "Fuzz: shares minted must be exact");

        // Invariant 2: total supply increased exactly
        assertEq(vault.totalSupply(), initialTotalSupply + sharesToMint, "Fuzz: total supply must increase by shares");

        // Invariant 3: total assets increased
        assertEq(
            vault.totalAssets(), initialTotalAssets + assetsUsed, "Fuzz: total assets must increase by assets used"
        );

        // Invariant 4: mint did not exceed previewMint
        assertLe(assetsUsed, requiredAssets, "Fuzz: assetsUsed must not exceed previewMint");

        // Invariant 5: assets used must be > 0 for any non-zero shares >= 1e18
        assertGt(assetsUsed, 0, "Fuzz: assets used must be > 0 for >= 1e18 shares");
    }

    /// @notice Fuzz: mint then verify convertToAssets of minted shares returns at least the assets paid
    ///         minus an acceptable rounding tolerance
    function test_mint_fuzz_sharesValueAfterMint(uint256 sharesToMint) public {
        sharesToMint = bound(sharesToMint, 1e18, 10_000_000e18);

        uint256 requiredAssets = vault.previewMint(sharesToMint);
        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        uint256 sharesValue = vault.convertToAssets(sharesToMint);

        // The value of shares should be close to assets used.
        // convertToAssets rounds down, previewMint rounds up, so sharesValue <= assetsUsed.
        assertLe(sharesValue, assetsUsed, "Fuzz: shares value should be <= assets used (rounding)");

        // But the difference should be at most 2 wei (rounding in each direction)
        assertApproxEqAbs(sharesValue, assetsUsed, 2, "Fuzz: shares value should be within 2 wei of assets used");
    }

    /// @notice Fuzz: mint and deposit of equivalent amounts should yield equivalent results
    function test_mint_fuzz_mintVsDeposit_equivalence(uint256 depositAmount) public {
        // Bound USDC deposit amount: 1 USDC to 10M USDC
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6);

        // Path A: deposit assets -> get shares
        uint256 snapshotId = vm.snapshot();

        deal(MC.USDC, alice, depositAmount);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        uint256 sharesFromDeposit = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        uint256 totalSupplyAfterDeposit = vault.totalSupply();

        vm.revertTo(snapshotId);

        // Path B: mint the same number of shares
        uint256 requiredAssets = vault.previewMint(sharesFromDeposit);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesFromDeposit, alice);
        vm.stopPrank();

        // Shares should be identical
        assertEq(vault.balanceOf(alice), sharesFromDeposit, "Mint and deposit should yield same shares");

        // Assets should be within 1 wei (rounding differences between Floor and Ceil)
        assertApproxEqAbs(assetsUsed, depositAmount, 1, "Mint and deposit should consume approximately same assets");

        // Total supply should match
        assertEq(
            vault.totalSupply(), totalSupplyAfterDeposit, "Total supply should match between mint and deposit paths"
        );

        // Total assets should be within 1 wei
        assertApproxEqAbs(
            vault.totalAssets(), totalAssetsAfterDeposit, 1, "Total assets should match between mint and deposit paths"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // DUST / SUB-DECIMAL SHARES (18-dec shares vs 6-dec USDC)
    // ─────────────────────────────────────────────────────────────────────

    /// @notice previewMint returns 0 USDC for sub-1e12 shares due to decimal truncation
    function test_mint_dustSharesBelowBoundary_previewReturnsZero() public view {
        // 12-decimal gap creates a free share zone below ~1e12
        uint256[5] memory dustAmounts = [uint256(1), 100, 1e6, 1e9, 1e11];

        for (uint256 i = 0; i < dustAmounts.length; i++) {
            uint256 sharesToMint = dustAmounts[i];
            uint256 requiredAssets = vault.previewMint(sharesToMint);

            // previewMint returns 0 for all sub-1e12 amounts
            assertEq(requiredAssets, 0, "previewMint returns 0 for sub-1e12 shares due to decimal truncation");
        }
    }

    /// @notice Minting dust shares for free: users can mint < 1e12 shares at zero cost
    function test_mint_dustSharesFree_economicImpactNegligible() public {
        uint256 dustShares = 1e11; // largest sub-boundary dust amount
        uint256 initialTotalSupply = vault.totalSupply();

        // Mint succeeds with 0 USDC since previewMint returns 0
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), 0);
        uint256 assetsUsed = vault.mint(dustShares, alice);
        vm.stopPrank();

        assertEq(assetsUsed, 0, "Dust shares minted for 0 USDC");
        assertEq(vault.balanceOf(alice), dustShares, "Alice received dust shares");
        assertEq(vault.totalSupply(), initialTotalSupply + dustShares, "TotalSupply inflated by dust");

        uint256 dustValue = vault.convertToAssets(dustShares);
        assertEq(dustValue, 0, "Dust shares are worth 0 USDC");
    }

    /// @notice Repeated dust minting cannot accumulate meaningful value
    function test_mint_repeatedDust_cannotAccumulateMeaningfulValue() public {
        uint256 dustShares = 1e11; // Just below boundary
        uint256 iterations = 100;

        for (uint256 i = 0; i < iterations; i++) {
            vm.prank(alice);
            vault.mint(dustShares, alice);
        }

        uint256 totalDustShares = dustShares * iterations; // 1e13
        assertEq(vault.balanceOf(alice), totalDustShares, "Accumulated dust shares");

        uint256 totalValue = vault.convertToAssets(totalDustShares);
        assertLe(totalValue, 100, "Accumulated dust value should be negligible (< 100 USDC wei)");
    }

    /// @notice Minting exactly at the 1e12 boundary requires non-zero USDC
    function test_mint_exactDecimalBoundary_1e12() public {
        uint256 sharesToMint = 1e12;

        uint256 requiredAssets = vault.previewMint(sharesToMint);

        // At the boundary, previewMint should require at least 1 USDC wei
        assertGe(requiredAssets, 1, "Minting 1e12 shares should require at least 1 USDC wei");

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertGe(assetsUsed, 1, "1e12 shares must cost at least 1 USDC wei");
        assertEq(vault.balanceOf(alice), sharesToMint, "Should receive exact 1e12 shares");
    }

    /// @notice Fuzz: any shares >= 1e12 must cost > 0 USDC (above the free-mint boundary)
    function test_mint_fuzz_aboveBoundary_alwaysCostsAssets(uint256 sharesToMint) public {
        sharesToMint = bound(sharesToMint, 1e12, 10_000_000e18);

        uint256 requiredAssets = vault.previewMint(sharesToMint);
        assertGt(requiredAssets, 0, "Shares >= 1e12 must always cost > 0 USDC");

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertGt(assetsUsed, 0, "Shares >= 1e12 must consume > 0 USDC");
        assertEq(vault.balanceOf(alice), sharesToMint, "Must receive exact shares");
    }

    // ─────────────────────────────────────────────────────────────────────
    // ZERO AMOUNT EDGE CASES
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Minting zero shares should succeed with zero assets consumed (ERC4626 compliance)
    function test_mint_zeroShares() public {
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        uint256 requiredAssets = vault.previewMint(0);
        assertEq(requiredAssets, 0, "previewMint(0) should return 0");

        deal(MC.USDC, alice, 1e6);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), 1e6);
        uint256 assetsUsed = vault.mint(0, alice);
        vm.stopPrank();

        assertEq(assetsUsed, 0, "Minting 0 shares should consume 0 assets");
        assertEq(vault.balanceOf(alice), 0, "Alice should have 0 shares");
        assertEq(vault.totalAssets(), initialTotalAssets, "Total assets should remain unchanged");
        assertEq(vault.totalSupply(), initialTotalSupply, "Total supply should remain unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────
    // RATE MANIPULATION / INFLATION ATTACK SCENARIOS
    // ─────────────────────────────────────────────────────────────────────

    /// @notice After a donation (rate increase), minting should still be fair.
    ///         A user should not get more shares per USDC than the current rate warrants.
    function test_mint_afterDonation_rateIsRespected() public {
        address donor = address(0xD0);

        // Record initial rate
        uint256 rateBeforeDonation = vault.convertToAssets(1e18);

        // Donor donates 10,000 USDC directly to vault
        uint256 donationAmount = 10_000e6;
        deal(MC.USDC, donor, donationAmount);
        vm.prank(donor);
        IERC20(MC.USDC).transfer(address(vault), donationAmount);

        // Rate should increase
        uint256 rateAfterDonation = vault.convertToAssets(1e18);
        assertGt(rateAfterDonation, rateBeforeDonation, "Rate should increase after donation");

        // Now mint shares: should cost more USDC per share
        uint256 sharesToMint = 1000e18;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        // Required assets should reflect the higher rate
        uint256 requiredAssetsAtOldRate = sharesToMint.mulDiv(rateBeforeDonation, 1e18, Math.Rounding.Ceil);
        assertGt(
            requiredAssets, requiredAssetsAtOldRate, "Post-donation mint should require more USDC than at old rate"
        );

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Verify the shares are worth approximately what was paid
        uint256 sharesValue = vault.convertToAssets(sharesToMint);
        assertApproxEqAbs(sharesValue, assetsUsed, 2, "Minted shares value should approximate assets paid");
    }

    /// @notice Multiple sequential mints should not degrade the exchange rate.
    ///         Verifies no cumulative rounding drift that could be exploited.
    function test_mint_sequential_noRateDrift() public {
        uint256 initialRate = vault.convertToAssets(1e18);

        // Perform 10 sequential mints of varying sizes
        uint256[10] memory mintAmounts =
            [uint256(1e18), 10e18, 100e18, 1000e18, 5000e18, 100e18, 50e18, 10e18, 1e18, 1e18];

        for (uint256 i = 0; i < mintAmounts.length; i++) {
            address minter = address(uint160(0x1000 + i));
            uint256 shares = mintAmounts[i];
            uint256 required = vault.previewMint(shares);

            deal(MC.USDC, minter, required);
            vm.startPrank(minter);
            IERC20(MC.USDC).approve(address(vault), required);
            vault.mint(shares, minter);
            vm.stopPrank();
        }

        uint256 finalRate = vault.convertToAssets(1e18);

        // Rate should stay the same or only increase (never decrease due to rounding favoring vault)
        assertGe(finalRate, initialRate, "Rate must not decrease after sequential mints");

        // Rate drift should be negligible (within 1 bps = 0.01%)
        assertApproxEqRel(finalRate, initialRate, 1e14, "Rate drift after 10 mints should be < 0.01%");
    }

    // ─────────────────────────────────────────────────────────────────────
    // LARGE AMOUNT EDGE CASES
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mint a very large amount of shares (approaches max deposit limits)
    function test_mint_largeAmount() public {
        uint256 sharesToMint = 100_000_000e18; // 100M shares
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), sharesToMint, "Should mint exact large amount of shares");
        assertGt(assetsUsed, 0, "Large mint should consume assets");

        // Rate should be preserved
        uint256 sharesValue = vault.convertToAssets(sharesToMint);
        assertApproxEqAbs(sharesValue, assetsUsed, 2, "Large mint shares value should match assets paid");
    }

    // ─────────────────────────────────────────────────────────────────────
    // PAUSED STATE
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mint should revert when vault is paused
    function test_mint_revertWhenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        uint256 sharesToMint = 1000e18;

        deal(MC.USDC, alice, 1000e6);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.expectRevert();
        vault.mint(sharesToMint, alice);
        vm.stopPrank();
    }

    /// @notice maxMint should return 0 when paused
    function test_maxMint_returnsZeroWhenPaused() public {
        vm.prank(PAUSER);
        vault.pause();

        assertEq(vault.maxMint(alice), 0, "maxMint should return 0 when paused");
    }

    /// @notice maxMint should return type(uint256).max when not paused
    function test_maxMint_returnsMaxWhenNotPaused() public view {
        assertEq(vault.maxMint(alice), type(uint256).max, "maxMint should return max uint256 when not paused");
    }

    // ─────────────────────────────────────────────────────────────────────
    // APPROVAL / ALLOWANCE EDGE CASES
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Mint should revert if caller has insufficient USDC allowance
    function test_mint_revertInsufficientAllowance() public {
        uint256 sharesToMint = 1000e18;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets);
        vm.startPrank(alice);
        // Approve less than needed
        IERC20(MC.USDC).approve(address(vault), requiredAssets - 1);
        vm.expectRevert();
        vault.mint(sharesToMint, alice);
        vm.stopPrank();
    }

    /// @notice Mint should revert if caller has insufficient USDC balance
    function test_mint_revertInsufficientBalance() public {
        uint256 sharesToMint = 1000e18;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        // Give less than required
        deal(MC.USDC, alice, requiredAssets - 1);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        vm.expectRevert();
        vault.mint(sharesToMint, alice);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    // ERC4626 COMPLIANCE: PREVIEW VS ACTUAL
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Fuzz: previewMint must always be >= actual assetsUsed (ERC4626 spec)
    function test_mint_fuzz_previewMintUpperBound(uint256 sharesToMint) public {
        sharesToMint = bound(sharesToMint, 1e12, 100_000_000e18);

        uint256 preview = vault.previewMint(sharesToMint);
        assertGt(preview, 0, "previewMint must return > 0 for shares >= 1e12");

        deal(MC.USDC, alice, preview);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), preview);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertLe(assetsUsed, preview, "ERC4626: actual mint cost must never exceed previewMint");
    }

    /// @notice previewMint and previewDeposit should be near-inverses for meaningful amounts.
    ///         Due to Ceil/Floor rounding + the 12-decimal gap, there is quantization error
    ///         of up to 1e12 shares (= 1 USDC wei worth of shares).
    function test_mint_previewMint_previewDeposit_nearInverse() public view {
        uint256 sharesToMint = 5000e18;

        // previewMint: shares -> required assets
        uint256 assetsNeeded = vault.previewMint(sharesToMint);

        // previewDeposit: assets -> shares received
        uint256 sharesFromAssets = vault.previewDeposit(assetsNeeded);

        // Due to Ceil then Floor rounding + decimal gap, the round-trip may differ
        // by up to 1e12 shares (the quantization unit for 6-dec USDC -> 18-dec shares)
        assertApproxEqAbs(
            sharesFromAssets,
            sharesToMint,
            1e12,
            "previewMint and previewDeposit should be near-inverses within 1e12 quantization"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // MULTI-USER SCENARIOS
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Two users mint the same shares; both should pay the same assets
    function test_mint_twoUsers_samePriceFairness() public {
        uint256 sharesToMint = 500e18;

        // Alice mints
        uint256 requiredA = vault.previewMint(sharesToMint);
        deal(MC.USDC, alice, requiredA);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredA);
        uint256 assetsUsedA = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Bob mints the same amount immediately after
        uint256 requiredB = vault.previewMint(sharesToMint);
        deal(MC.USDC, bob, requiredB);
        vm.startPrank(bob);
        IERC20(MC.USDC).approve(address(vault), requiredB);
        uint256 assetsUsedB = vault.mint(sharesToMint, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), sharesToMint, "Alice should have exact shares");
        assertEq(vault.balanceOf(bob), sharesToMint, "Bob should have exact shares");

        // Both should pay the same amount (rate preserved, mint favors vault on rounding)
        assertApproxEqAbs(
            assetsUsedA, assetsUsedB, 1, "Two users minting same shares should pay approximately the same"
        );
    }

    /// @notice Deposit then mint by same user: verify total shares are additive
    function test_mint_afterDeposit_sharesAreAdditive() public {
        // First deposit
        uint256 depositAmount = 1000e6;
        deal(MC.USDC, alice, depositAmount);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        uint256 depositShares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Then mint additional shares
        uint256 mintShares = 500e18;
        uint256 required = vault.previewMint(mintShares);
        deal(MC.USDC, alice, required);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), required);
        vault.mint(mintShares, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), depositShares + mintShares, "Shares from deposit and mint should be additive");
    }

    // ─────────────────────────────────────────────────────────────────────
    // ROUNDING DIRECTION VERIFICATION
    // ─────────────────────────────────────────────────────────────────────

    /// @notice Verify that mint rounding favors the vault
    function test_mint_roundsInFavorOfVault() public view {
        // Use a whole-share amount to avoid sub-1e12 quantization issues
        uint256 sharesToMint = 1000e18;

        uint256 assetsForMint = vault.previewMint(sharesToMint);
        uint256 sharesForDeposit = vault.previewDeposit(assetsForMint);

        // The difference should be very small relative to the minted amount
        uint256 diff = sharesToMint - sharesForDeposit;
        uint256 relativeDiffBps = (diff * 10_000) / sharesToMint;

        assertLe(
            relativeDiffBps,
            1, // Less than 0.01% loss
            "Roundtrip precision loss should be negligible"
        );

        // Verify the direction: deposit gives fewer shares (vault-favorable)
        assertLe(
            sharesForDeposit,
            sharesToMint,
            "previewDeposit of previewMint assets should yield <= shares (vault keeps rounding surplus)"
        );
    }

    /// @notice Fuzz: for shares above the boundary, convertToAssets(floor) <= previewMint(ceil)
    function test_mint_fuzz_roundingConsistency(uint256 sharesToMint) public view {
        sharesToMint = bound(sharesToMint, 1e12, 100_000_000e18);

        uint256 assetsRequired = vault.previewMint(sharesToMint);
        assertGt(assetsRequired, 0, "previewMint must return > 0 for shares >= 1e12");

        // convertToAssets (floor) should be <= previewMint (ceil) for equivalent amounts
        uint256 assetsFloor = vault.convertToAssets(sharesToMint);
        assertLe(assetsFloor, assetsRequired, "convertToAssets(floor) must be <= previewMint(ceil)");
    }

    // ─────────────────────────────────────────────────────────────────────
    // DUST MINT ACCUMULATION: BOUNDARY CROSSING
    // ─────────────────────────────────────────────────────────────────────

    /// @notice When accumulated free dust shares cross the 1e12 boundary,
    ///         they gain non-zero value. Verify total gained value is negligible.
    function test_mint_dustAccumulation_crossesBoundary() public {
        uint256 dustShares = 1e11;
        uint256 iterations = 20; // Accumulate 2e12 shares total

        for (uint256 i = 0; i < iterations; i++) {
            vm.prank(alice);
            vault.mint(dustShares, alice);
        }

        uint256 totalShares = vault.balanceOf(alice);
        assertEq(totalShares, dustShares * iterations, "All dust shares accumulated");

        uint256 value = vault.convertToAssets(totalShares);
        assertLe(value, 10, "Value of accumulated dust shares should be < 10 USDC wei");
    }

    /// @notice Compare: minting 1e13 shares at once vs 100x dust mints of 1e11
    function test_mint_dustVsDirect_roundingBenefitCapped() public {
        // Path A: mint 1e13 shares directly (costs USDC)
        uint256 directShares = 1e13;
        uint256 directCost = vault.previewMint(directShares);
        assertGt(directCost, 0, "Direct 1e13 mint costs USDC");

        // Path B: 100x dust mints of 1e11 (free per iteration)
        uint256 snapshotId = vm.snapshot();

        for (uint256 i = 0; i < 100; i++) {
            vm.prank(alice);
            vault.mint(1e11, alice);
        }
        uint256 dustTotal = vault.balanceOf(alice); // 1e13

        vm.revertTo(snapshotId);

        assertEq(dustTotal, directShares, "Both paths accumulate same total shares");

        assertLe(directCost, 100, "Direct cost of 1e13 shares is tiny (< 100 USDC wei)");
    }
}
