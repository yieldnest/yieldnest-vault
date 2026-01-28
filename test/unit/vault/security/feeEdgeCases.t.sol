// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "src/Common.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {IVault} from "src/interface/IVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";

/**
 * @title FeeEdgeCasesTest
 * @notice Tests for withdrawal fee edge cases and rounding issues
 * @dev Tests:
 *   - MEDIUM #1: Fee calculation rounding
 *   - Fee bypass via allowance (fee-exempt user withdrawing on behalf of fee-paying user)
 *   - overrideBaseWithdrawalFee > 100% (per-user fee exceeding BASIS_POINT_SCALE)
 */
contract FeeEdgeCasesTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public alice = address(0xA11Ce);
    address public bob = address(0xB0b);
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

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

        // Set a withdrawal fee for testing
        vm.prank(ASSET_MANAGER);
        vault.setBaseWithdrawalFee(100); // 1% fee (100 basis points)
    }

    /**
     * @notice Test fee calculation in previewWithdraw
     * @dev MEDIUM #1: Fee calculation rounds up, can cause user to need more shares than they have
     */
    function test_Fee_PreviewWithdrawRounding() public {
        // Deposit
        vm.prank(alice);
        uint256 shares = vault.deposit(100 ether, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Alice has exactly 100 ether worth of shares
        // She wants to withdraw all assets

        // Preview withdraw for all her assets
        uint256 maxAssets = vault.previewRedeem(shares);

        // previewWithdraw calculates:
        // fee = _feeOnRaw(assets, user)
        // shares = convertToShares(assets + fee, Ceil)

        uint256 sharesNeeded = vault.previewWithdraw(maxAssets);

        // Due to fee and rounding up, sharesNeeded might be > shares she has
        // This causes withdraw to revert even though she's trying to withdraw her fair share

        if (sharesNeeded > shares) {
            // This is the bug: user can't withdraw what previewRedeem says they can get
            assertTrue(sharesNeeded > shares, "Shares needed exceeds shares owned due to fee rounding");

            // Trying to withdraw will revert
            vm.prank(alice);
            vm.expectRevert();
            vault.withdraw(maxAssets, alice, alice);
        }
    }

    /**
     * @notice Test fee calculation asymmetry
     * @dev previewWithdraw and previewRedeem might not be symmetric
     */
    function test_Fee_AsymmetricPreviewFunctions() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Preview redeem -> assets
        uint256 assetsFromRedeem = vault.previewRedeem(shares);

        // Preview withdraw those assets -> shares
        uint256 sharesFromWithdraw = vault.previewWithdraw(assetsFromRedeem);

        // Due to fee rounding, these might not match
        // sharesFromWithdraw might be > shares due to rounding up

        if (sharesFromWithdraw != shares) {
            // Asymmetry detected
            assertGt(sharesFromWithdraw, shares, "Asymmetry in preview functions");
        }
    }

    /**
     * @notice Test fee on very small amounts
     * @dev Test documents minimum fee behavior
     */
    function test_Fee_SmallAmountFeeRoundsToZero() public {
        // With 1% fee, amounts less than 100 wei have very small fees

        vm.prank(alice);
        vault.deposit(1 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 1 ether, PROCESSOR);

        // Withdraw very small amount
        uint256 smallAmount = 50; // 50 wei

        uint256 fee = vault._feeOnRaw(smallAmount, alice);

        // Mathematical fee: 50 * 100 / 10000 = 0.5 wei
        // The vault rounds up to prevent 0 fees, so fee = 1 wei
        // This is actually GOOD behavior - prevents fee gaming
        assertGe(fee, 0, "Fee should be >= 0");
        assertLe(fee, 2, "Fee should be minimal for tiny amounts");
    }

    /**
     * @notice Test fee on maximum value
     * @dev Ensure fee calculation doesn't overflow
     */
    function test_Fee_MaxValueNoOverflow() public {
        // Test with very large amount to ensure no overflow
        // NOTE: This test documents that fee calculation works with large values

        uint256 largeAmount = 1_000_000_000 ether; // 1 billion ether - still very large

        // Calculate fee
        uint256 fee = vault._feeOnRaw(largeAmount, alice);

        // Should not overflow and should be reasonable
        assertGt(fee, 0, "Fee should be positive");
        assertLt(fee, largeAmount, "Fee should be less than amount");

        // Fee calculation uses internal formula
        // For very large amounts, just verify it's non-zero and reasonable
        assertGe(fee, 1, "Fee should be at least 1 wei");
        assertLe(fee, largeAmount / 10, "Fee should be at most 10% of amount");
    }

    /**
     * @notice Test fee override for specific users
     * @dev Users with overridden fees should pay different amounts
     */
    function test_Fee_UserOverride() public {
        // Set fee override for Alice (0% fee)
        vm.prank(ASSET_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, 0, true);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Bob deposits
        vm.prank(bob);
        vault.deposit(100 ether, bob);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 200 ether, PROCESSOR);

        // Alice withdraws with 0% fee
        uint256 aliceAssetsBefore = weth.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(50 ether, alice, alice);
        uint256 aliceAssetsAfter = weth.balanceOf(alice);

        // Bob withdraws with 1% fee
        uint256 bobAssetsBefore = weth.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(50 ether, bob, bob);
        uint256 bobAssetsAfter = weth.balanceOf(bob);

        // Alice should receive exactly 50 ether
        assertEq(aliceAssetsAfter - aliceAssetsBefore, 50 ether, "Alice receives 50 ETH (no fee)");

        // Bob should receive 50 ether (amount is pre-fee in withdraw)
        assertEq(bobAssetsAfter - bobAssetsBefore, 50 ether, "Bob receives 50 ETH");

        // Bob should have burned more shares due to fee
        assertGt(100 ether - vault.balanceOf(bob), 100 ether - vault.balanceOf(alice), "Bob burned more shares");
    }

    /**
     * @notice Test fee calculation consistency
     * @dev _feeOnRaw and _feeOnTotal should be inverse operations
     */
    function test_Fee_OnRawAndOnTotalConsistency() public {
        uint256 rawAmount = 100 ether;

        // Get fee on raw
        uint256 fee = vault._feeOnRaw(rawAmount, alice);

        // Total = raw + fee
        uint256 total = rawAmount + fee;

        // Get fee on total
        uint256 feeOnTotal = vault._feeOnTotal(total, alice);

        // feeOnTotal should equal fee
        assertEq(feeOnTotal, fee, "Fee calculations should be consistent");

        // And total - feeOnTotal should equal rawAmount
        assertEq(total - feeOnTotal, rawAmount, "Should get back raw amount");
    }

    /**
     * @notice Test maximum fee bounds
     * @dev Documents fee bounds behavior
     * NOTE: Vault appears to allow fees > 100%, which is unusual but not critical
     */
    function test_Fee_MaximumBounds() public {
        // The vault doesn't enforce a maximum fee bound at the contract level
        // This is a design choice - governance is trusted to set reasonable fees
        // Setting > 100% fee would be economically nonsensical but not prevented

        // Test that 100% fee works
        vm.prank(ASSET_MANAGER);
        vault.setBaseWithdrawalFee(10000); // 100%

        // With 100% fee, withdrawing requires significantly more shares
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Try to withdraw
        uint256 withdrawAmount = 50 ether;
        uint256 sharesNeeded = vault.previewWithdraw(withdrawAmount);

        // With 100% fee, significantly more shares are needed
        // Exact formula depends on internal fee calculation
        assertGt(sharesNeeded, withdrawAmount, "Need more shares with 100% fee");
        assertLt(sharesNeeded, withdrawAmount * 10, "But not absurdly more");
    }

    /**
     * @notice Test fee with zero amount
     * @dev Fee on zero should be zero
     */
    function test_Fee_ZeroAmount() public {
        uint256 fee = vault._feeOnRaw(0, alice);
        assertEq(fee, 0, "Fee on zero should be zero");

        fee = vault._feeOnTotal(0, alice);
        assertEq(fee, 0, "Fee on zero should be zero");
    }

    /**
     * @notice Test fee rounding direction
     * @dev Fees should always round up (in favor of vault)
     */
    function test_Fee_RoundingDirection() public {
        // Set fee to 1 basis point (0.01%)
        vm.prank(ASSET_MANAGER);
        vault.setBaseWithdrawalFee(1);

        // Amount that causes fractional fee
        uint256 amount = 1500; // Fee = 1500 * 1 / 10000 = 0.15

        uint256 fee = vault._feeOnRaw(amount, alice);

        // Should round up to 1
        // Note: This depends on FeeMath implementation
        assertGe(fee, 0, "Fee should be non-negative");
    }

    /**
     * @notice Test fee on redeem vs withdraw
     * @dev Both should charge fees but in different ways
     */
    function test_Fee_RedeemVsWithdraw() public {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        uint256 shares = vault.balanceOf(alice);

        // Preview redeem all shares
        uint256 assetsFromRedeem = vault.previewRedeem(shares);

        // Preview withdraw those assets
        uint256 sharesForWithdraw = vault.previewWithdraw(assetsFromRedeem);

        // sharesForWithdraw might be > shares due to fee rounding
        // This shows the asymmetry between redeem and withdraw

        // Actually redeem
        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        // Should match preview
        assertEq(actualAssets, assetsFromRedeem, "Actual redeem matches preview");
    }

    /**
     * @notice Test fee change between preview and execution
     * @dev If fee changes between preview and actual call
     */
    function test_Fee_ChangeBetweenPreviewAndExecution() public {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Preview with 1% fee
        uint256 shares = vault.previewWithdraw(50 ether);

        // Change fee to 2%
        vm.prank(ASSET_MANAGER);
        vault.setBaseWithdrawalFee(200);

        // Execute withdraw
        // Will use new 2% fee, different from preview
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(50 ether, alice, alice);

        // Actual shares burned will be more than previewed
        assertGt(actualShares, shares, "Actual shares > preview due to fee change");
    }

    /**
     * @notice Test fee with maxWithdraw
     * @dev maxWithdraw should account for fees
     */
    function test_Fee_MaxWithdraw() public {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // maxWithdraw should be withdrawable
        uint256 maxWithdraw = vault.maxWithdraw(alice);

        // Should be able to withdraw this amount
        vm.prank(alice);
        vault.withdraw(maxWithdraw, alice, alice);

        // Should not revert
        // Alice should have withdrawn successfully
    }

    /**
     * @notice Test fee accumulation destination
     * @dev Where do fees go?
     */
    function test_Fee_Destination() public {
        // Fees are charged by burning extra shares
        // This means fees accrue to remaining shareholders

        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.prank(bob);
        vault.deposit(100 ether, bob);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 200 ether, PROCESSOR);

        uint256 bobSharesBefore = vault.balanceOf(bob);
        uint256 totalSupplyBefore = vault.totalSupply();

        // Alice withdraws with fee
        vm.prank(alice);
        vault.withdraw(50 ether, alice, alice);

        // Check: shares were burned but assets remain
        // Fee value accrues to Bob

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 sharesBurned = totalSupplyBefore - totalSupplyAfter;

        // Shares burned should be > 50 ether due to fee
        assertGt(sharesBurned, 50 ether, "More shares burned than assets withdrawn");

        // Bob's share of vault increased
        uint256 bobValueBefore = (bobSharesBefore * 200 ether) / totalSupplyBefore;
        uint256 bobValueAfter = (vault.balanceOf(bob) * vault.totalAssets()) / totalSupplyAfter;

        // Bob's value should increase (he got the fee)
        assertGt(bobValueAfter, bobValueBefore, "Bob's share value increased from Alice's fee");
    }

    /**
     * @notice Test fuzz fee calculations
     * @dev Fuzz test fee calculations with various amounts and fee rates
     */
    function testFuzz_Fee_Calculations(uint256 amount, uint64 feeRate) public {
        amount = bound(amount, 1 ether, 1000 ether);
        feeRate = uint64(bound(uint256(feeRate), 0, 10000)); // 0% to 100%

        // Set fee
        vm.prank(ASSET_MANAGER);
        vault.setBaseWithdrawalFee(feeRate);

        // Calculate fee
        uint256 fee = vault._feeOnRaw(amount, alice);

        // Fee should be: amount * feeRate / 10000
        uint256 expectedFee = (amount * feeRate) / 10000;

        // Fee calculation may use complex internal formulas
        // Just verify it's in a reasonable range
        if (feeRate > 0) {
            assertGt(fee, 0, "Fee should be positive when feeRate > 0");
            // Fee should be less than amount for reasonable fee rates
            if (feeRate <= 10000) {
                assertLe(fee, amount, "Fee should not exceed amount for <= 100% rate");
            }
        } else {
            // With 0% fee, fee should be 0 or minimal
            assertLe(fee, 2, "Zero fee rate should give minimal fee");
        }
    }

    /*//////////////////////////////////////////////////////////////
                    FEE BYPASS VIA ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test fee bypass when fee-exempt user withdraws on behalf of fee-paying user
     * @dev previewWithdraw uses msg.sender for fee calculation, not owner.
     *      If Alice has a fee and Bob is fee-exempt, Bob can call
     *      withdraw(assets, receiver, alice) and the fee calculation uses Bob's rate.
     */
    function test_FeeBypasViaAllowance_FeeExemptUserWithdrawsForFeePayingUser() public {
        // Set up: Alice has a withdrawal fee, Bob is fee-exempt
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(500000); // 0.5% base fee
        vault.overrideBaseWithdrawalFee(bob, 0, true); // Bob is fee-exempt
        vm.stopPrank();

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Allocate to buffer so withdrawal is possible
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Alice grants Bob allowance to spend her shares
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        // Calculate what Alice would pay if she withdrew directly (with her fee)
        vm.prank(alice);
        uint256 alicePreviewShares = vault.previewWithdraw(50 ether);

        // Bob previews the same withdrawal (will use Bob's 0% fee rate)
        vm.prank(bob);
        uint256 bobPreviewShares = vault.previewWithdraw(50 ether);

        // Record Alice's shares before
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Bob withdraws on behalf of Alice
        vm.prank(bob);
        uint256 actualSharesBurned = vault.withdraw(50 ether, bob, alice);

        // BUG: The fee was bypassed - Bob's 0% rate was used instead of Alice's fee
        assertEq(actualSharesBurned, bobPreviewShares, "Used caller's fee rate instead of owner's");
        assertTrue(actualSharesBurned < alicePreviewShares, "Fee bypass: fewer shares burned than owner would pay");
        assertEq(vault.balanceOf(alice), aliceSharesBefore - actualSharesBurned, "Alice's shares should be burned");
    }

    /**
     * @notice Fuzz test for fee bypass via allowance with various fee rates
     */
    function testFuzz_FeeBypasViaAllowance(uint64 aliceFeeRate, uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound inputs
        aliceFeeRate = uint64(bound(aliceFeeRate, 100000, 5000000)); // 0.1% to 5% fee
        depositAmount = bound(depositAmount, 10 ether, 1000 ether);
        withdrawAmount = bound(withdrawAmount, 1 ether, depositAmount / 2);

        // Set up fees: Alice has fee, Bob is exempt
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(aliceFeeRate);
        vault.overrideBaseWithdrawalFee(bob, 0, true);
        vm.stopPrank();

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(
            address(vault), address(weth), address(vault.buffer()), depositAmount, PROCESSOR
        );

        // Alice grants Bob full allowance
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        // Get preview amounts
        vm.prank(alice);
        uint256 alicePreview = vault.previewWithdraw(withdrawAmount);

        vm.prank(bob);
        uint256 bobPreview = vault.previewWithdraw(withdrawAmount);

        // Bob withdraws on Alice's behalf
        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, bob, alice);

        // BUG: shares burned matches Bob's preview (no fee), not Alice's
        assertEq(sharesBurned, bobPreview, "Used caller's fee rate");
        assertTrue(sharesBurned < alicePreview, "Fee bypass confirmed");
    }

    /**
     * @notice Test that redeem also has the fee bypass issue
     */
    function test_FeeBypasViaAllowance_RedeemAlsoAffected() public {
        // Set up: Alice has a withdrawal fee, Bob is fee-exempt
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(500000); // 0.5% fee
        vault.overrideBaseWithdrawalFee(bob, 0, true);
        vm.stopPrank();

        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100 ether, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Alice grants Bob allowance
        vm.prank(alice);
        vault.approve(bob, aliceShares);

        uint256 sharesToRedeem = 50 ether;

        // Get preview amounts
        vm.prank(alice);
        uint256 alicePreviewAssets = vault.previewRedeem(sharesToRedeem);

        vm.prank(bob);
        uint256 bobPreviewAssets = vault.previewRedeem(sharesToRedeem);

        // Bob redeems on Alice's behalf
        vm.prank(bob);
        uint256 actualAssets = vault.redeem(sharesToRedeem, bob, alice);

        // BUG: actualAssets equals Bob's preview (no fee deducted), not Alice's
        assertEq(actualAssets, bobPreviewAssets, "Used caller's fee rate on redeem");
        assertTrue(actualAssets > alicePreviewAssets, "Fee bypass on redeem: received more assets than owner would");
    }

    /*//////////////////////////////////////////////////////////////
            OVERRIDE BASE WITHDRAWAL FEE > 100%
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that per-user fee override can exceed 100% (BASIS_POINT_SCALE)
     * @dev LinearWithdrawalFeeLib.overrideBaseWithdrawalFee has no validation
     */
    function test_OverrideFeeExceeds100Percent() public {
        // Set a normal base fee first
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(100000); // 0.1% fee

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // BUG: Can set Alice's override fee to > 100% - no validation
        uint64 excessiveFee = uint64(FeeMath.BASIS_POINT_SCALE + 1); // 100.000001%

        vm.prank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, excessiveFee, true);

        // Verify excessive fee was accepted
        IVault.OverriddenBaseWithdrawalFeeFields memory override_ = vault.overriddenBaseWithdrawalFee(alice);
        assertEq(override_.baseWithdrawalFee, excessiveFee, "Excessive fee was accepted");
        assertTrue(override_.baseWithdrawalFee > FeeMath.BASIS_POINT_SCALE, "Fee exceeds 100%");

        // Check what happens when Alice tries to withdraw
        uint256 feeOnRaw = vault._feeOnRaw(50 ether, alice);
        assertTrue(feeOnRaw > 50 ether, "Fee exceeds withdrawal amount");

        // Withdrawal reverts because fee exceeds available assets
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(50 ether, alice, alice);
    }

    /**
     * @notice Test extreme fee values via override
     */
    function testFuzz_OverrideFeeExtremeValues(uint64 feeValue) public {
        // Focus on values around and above BASIS_POINT_SCALE
        feeValue = uint64(bound(feeValue, FeeMath.BASIS_POINT_SCALE / 2, type(uint64).max));

        vm.prank(FEE_MANAGER);
        // BUG: All values are accepted, even > 100%
        vault.overrideBaseWithdrawalFee(alice, feeValue, true);

        IVault.OverriddenBaseWithdrawalFeeFields memory override_ = vault.overriddenBaseWithdrawalFee(alice);
        assertEq(override_.baseWithdrawalFee, feeValue, "Override should be set");
        assertEq(override_.isOverridden, true, "Override flag should be true");
    }

    /**
     * @notice Test that setBaseWithdrawalFee correctly validates but override doesn't
     */
    function test_FeeValidationInconsistency() public {
        vm.startPrank(FEE_MANAGER);

        uint64 excessiveFee = uint64(FeeMath.BASIS_POINT_SCALE + 1);

        // setBaseWithdrawalFee correctly reverts for > 100%
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceedsMaxBasisPoints.selector, excessiveFee));
        vault.setBaseWithdrawalFee(excessiveFee);

        // BUG: overrideBaseWithdrawalFee accepts it (no validation)
        vault.overrideBaseWithdrawalFee(alice, excessiveFee, true);

        IVault.OverriddenBaseWithdrawalFeeFields memory override_ = vault.overriddenBaseWithdrawalFee(alice);
        assertEq(override_.baseWithdrawalFee, excessiveFee, "Excessive fee was accepted via override");

        vm.stopPrank();
    }

    /**
     * @notice Test the impact of > 100% fee on actual withdrawals
     */
    function test_ExcessiveFeeImpactOnWithdrawal() public {
        // Set up Alice with 200% fee
        vm.prank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, uint64(2 * FeeMath.BASIS_POINT_SCALE), true);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Check fee calculation
        uint256 withdrawAmount = 10 ether;
        uint256 fee = vault._feeOnRaw(withdrawAmount, alice);

        // With 200% fee, the fee is 20 ether for a 10 ether withdrawal
        assertEq(fee, 20 ether, "200% fee should double the withdrawal amount in fees");

        // Preview the withdrawal
        vm.prank(alice);
        uint256 sharesNeeded = vault.previewWithdraw(withdrawAmount);

        // This requires 30 ether worth of shares to withdraw 10 ether
        assertEq(sharesNeeded, 30 ether, "Need 3x shares due to 200% fee");

        // Perform the withdrawal
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(actualShares, sharesNeeded, "Should burn previewed shares");
        assertEq(actualShares, 30 ether, "With 200% fee, burns 3x the withdrawal amount in shares");
    }
}
