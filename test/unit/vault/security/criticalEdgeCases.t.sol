// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {IVault} from "src/interface/IVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";

/**
 * @title CriticalEdgeCasesTest
 * @notice Tests for critical edge cases identified in security review
 * @dev Tests:
 *   - #6: Fee bypass via allowance (fee-exempt user withdrawing on behalf of fee-paying user)
 *   - #7: Zero shares on deposit (small deposits yielding 0 shares)
 *   - #3: overrideBaseWithdrawalFee > 100% (per-user fee exceeding BASIS_POINT_SCALE)
 */
contract CriticalEdgeCasesTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public alice = address(0xA11ce);
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
    }

    /*//////////////////////////////////////////////////////////////
                    #6: FEE BYPASS VIA ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test fee bypass when fee-exempt user withdraws on behalf of fee-paying user
     * @dev CRITICAL: previewWithdraw uses msg.sender for fee calculation, not owner
     *      This means if Alice has 5% fee and Bob has 0% fee, Bob can call
     *      withdraw(assets, receiver, alice) and the fee calculation uses Bob's rate
     */
    function test_FeeBypasViaAllowance_FeeExemptUserWithdrawsForFeePayingUser() public {
        // Set up: Alice has a 5% withdrawal fee, Bob is fee-exempt
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
        // actualSharesBurned equals bobPreviewShares, not alicePreviewShares
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
     * @notice Test that redeem also has the same issue
     */
    function test_FeeBypasViaAllowance_RedeemAlsoAffected() public {
        // Set up: Alice has a 5% withdrawal fee, Bob is fee-exempt
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
                    #7: ZERO SHARES ON DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that depositing a very small amount can result in zero shares
     * @dev When rate conversion or rounding causes shares to be 0, user loses funds
     */
    function test_ZeroSharesDeposit_SmallAmountYieldsZeroShares() public {
        // First, make a large deposit to establish a share price
        vm.prank(alice);
        vault.deposit(1000 ether, alice);

        // Simulate yield to increase share price (donate directly)
        deal(MC.WETH, address(vault), weth.balanceOf(address(vault)) + 100 ether);
        vault.processAccounting();

        // Now the share price is > 1:1
        uint256 tinyAmount = 1; // 1 wei

        uint256 bobSharesBefore = vault.balanceOf(bob);
        uint256 bobWethBefore = weth.balanceOf(bob);

        // Preview shows 0 shares for tiny amount
        uint256 previewShares = vault.previewDeposit(tinyAmount);
        assertEq(previewShares, 0, "Preview should return 0 shares for tiny amount");

        // BUG: Deposit is accepted with 0 shares minted - user loses funds
        vm.prank(bob);
        uint256 actualShares = vault.deposit(tinyAmount, bob);

        assertEq(actualShares, 0, "Zero shares minted");
        assertEq(vault.balanceOf(bob), bobSharesBefore, "Bob has same shares (0 minted)");
        assertLt(weth.balanceOf(bob), bobWethBefore, "Bob lost WETH without receiving shares");
    }

    /**
     * @notice Fuzz test to find deposit amounts that yield zero shares
     */
    function testFuzz_ZeroSharesDeposit(uint256 initialDeposit, uint256 yieldAmount, uint256 tinyDeposit) public {
        // Set up a vault with yield to create non-1:1 share price
        initialDeposit = bound(initialDeposit, 100 ether, 10000 ether);
        yieldAmount = bound(yieldAmount, 10 ether, initialDeposit / 2);
        tinyDeposit = bound(tinyDeposit, 1, 1000); // Very small amounts

        // Initial deposit
        vm.prank(alice);
        vault.deposit(initialDeposit, alice);

        // Simulate yield
        deal(MC.WETH, address(vault), weth.balanceOf(address(vault)) + yieldAmount);
        vault.processAccounting();

        // Check if tiny deposit yields 0 shares
        uint256 previewShares = vault.previewDeposit(tinyDeposit);

        if (previewShares == 0) {
            // Verify the deposit would be accepted with 0 shares (the bug)
            vm.prank(bob);
            uint256 actualShares = vault.deposit(tinyDeposit, bob);
            assertEq(actualShares, 0, "Zero shares minted for tiny deposit");
        }
    }

    /**
     * @notice Test zero shares with high-rate assets (like WBTC at 20 ETH)
     */
    function test_ZeroSharesDeposit_HighRateAsset() public {
        // WBTC has 8 decimals and rate of 20 ETH per WBTC in test setup
        address wbtc = MC.WBTC;

        // Make initial deposit to establish vault
        vm.prank(alice);
        vault.deposit(1000 ether, alice);

        // Small WBTC amount (1 satoshi = 1e-8 WBTC)
        uint256 tinySatoshis = 1; // 1 satoshi

        deal(wbtc, bob, tinySatoshis);
        vm.startPrank(bob);
        IERC20(wbtc).approve(address(vault), tinySatoshis);

        uint256 previewShares = vault.previewDeposit(tinySatoshis);

        if (previewShares == 0) {
            // BUG: Zero shares would be minted
            uint256 shares = vault.depositAsset(wbtc, tinySatoshis, bob);
            assertEq(shares, 0, "Zero shares minted for tiny WBTC deposit");
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
            #3: OVERRIDE BASE WITHDRAWAL FEE > 100%
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
        uint256 aliceShares = vault.deposit(100 ether, alice);

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
