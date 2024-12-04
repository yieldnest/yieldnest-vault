// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {console} from "lib/forge-std/src/console.sol";

contract FeeMathTest is Test {
    uint256 constant BASIS_POINT_SCALE = 1e8;
    uint256 constant BUFFER_FEE_FLAT_PORTION = 8e7; // 80%

    function test_LinearFee(uint256 amount, uint256 fee) public pure {
        // Bound fee to valid range (0 to BASIS_POINT_SCALE)
        fee = bound(fee, 0, BASIS_POINT_SCALE);

        // Bound amount to avoid overflow when multiplying by fee
        amount = bound(amount, 0, 1000000 ether);

        uint256 expectedFee = (amount * fee) / BASIS_POINT_SCALE;
        uint256 actualFee = FeeMath.linearFee(amount, fee, FeeMath.FeeType.OnRaw);

        assertApproxEqAbs(actualFee, expectedFee, 1, "Linear fee calculation incorrect");
    }

    function test_QuadraticBufferFee_FullBuffer(uint256 withdrawalAmount, uint256 bufferMaxSize, uint256 baseFee)
        public
        pure
    {
        uint256 bufferAvailable = bufferMaxSize; // Full buffer

        vm.assume(bufferMaxSize >= 10 && bufferMaxSize <= 100000 ether);
        vm.assume(
            withdrawalAmount > 0
                && withdrawalAmount <= bufferMaxSize * BUFFER_FEE_FLAT_PORTION / FeeMath.BASIS_POINT_SCALE
        );
        vm.assume(baseFee > 0 && baseFee <= FeeMath.BASIS_POINT_SCALE);
        vm.assume(baseFee <= FeeMath.BASIS_POINT_SCALE); // Ensure end >= start

        // With full buffer, should just be linear fee
        uint256 expectedFee = (withdrawalAmount * baseFee) / BASIS_POINT_SCALE; // Calculate expected fee using same formula as linearFee()
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, baseFee, FeeMath.FeeType.OnRaw
        );

        assertApproxEqAbs(actualFee, expectedFee, 1, "Full buffer fee calculation incorrect");
    }

    function test_QuadraticBufferFee_LowBuffer() public pure {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 100 ether; // Low buffer
        uint256 fee = 1e4; // 0.01% fee

        // With low buffer, fee should be higher than linear fee
        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee, FeeMath.FeeType.OnRaw);
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, fee, FeeMath.FeeType.OnRaw
        );

        // Expected fee calculation:
        // At 100 ether buffer (10% of max), we're well into the quadratic portion
        uint256 expectedFee = 58337500 * withdrawalAmount / BASIS_POINT_SCALE;

        assertEq(actualFee, expectedFee, "Low buffer fee calculation incorrect");
        assertTrue(actualFee > linearFee, "Low buffer fee should be higher than linear fee");
    }

    function test_QuadraticBufferFee_ZeroBuffer() public {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 0; // Zero buffer
        uint256 fee = 1e4; // 0.01% fee

        vm.expectRevert(
            abi.encodeWithSelector(FeeMath.WithdrawalExceedsBuffer.selector, withdrawalAmount, bufferAvailable)
        );
        FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, fee, FeeMath.FeeType.OnRaw
        );
    }

    function test_QuadraticBufferFee_PartialNonLinear() public pure {
        uint256 withdrawalAmount = 350 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 400 ether; // Just above non-linear threshold
        uint256 fee = 1e4;

        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, fee, FeeMath.FeeType.OnRaw
        );

        uint256 linearOnlyFee = FeeMath.linearFee(withdrawalAmount, fee, FeeMath.FeeType.OnRaw);
        assertGt(actualFee, linearOnlyFee, "Partial non-linear fee should be higher than pure linear fee");
    }

    function test_CalculateQuadraticTotalFee_PartialBuffer() public pure {
        uint256 baseFee = 1e6; // 1% base fee

        // Test interval [0.4, 0.6] normalized to BASIS_POINT_SCALE
        uint256 start = 4e7; // 0.4 * BASIS_POINT_SCALE
        uint256 end = 6e7; // 0.6 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 26080000, "Fee should equal expected");
    }

    function test_CalculateQuadraticTotalFee_LowBuffer() public pure {
        uint256 baseFee = 1e6; // 1% base fee

        // Test interval [0.1, 0.2] normalized to BASIS_POINT_SCALE
        uint256 start = 1e7; // 0.1 * BASIS_POINT_SCALE
        uint256 end = 2e7; // 0.2 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 3310000, "Fee should be higher in low buffer region");
    }

    function test_CalculateQuadraticTotalFee_OneWeiInterval() public pure {
        uint256 baseFee = 1e6; // 1% base fee

        // Test interval [0.1, 0.1 + i 1 wei] normalized to BASIS_POINT_SCALE
        uint256 start = 1e7; // 0.1 * BASIS_POINT_SCALE
        uint256 end = start + 1 wei; // 0.2 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 1990000, "Fee should be higher in low buffer region");
    }

    function test_CalculateQuadraticTotalFee_HighBuffer() public pure {
        uint256 baseFee = 1e6; // 1% base fee

        // Test interval [0.8, 0.9] normalized to BASIS_POINT_SCALE
        uint256 start = 8e7; // 0.8 * BASIS_POINT_SCALE
        uint256 end = 9e7; // 0.9 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 72610000, "Fee should be much higher in high buffer region");
    }

    function test_CalculateQuadraticTotalFee_FullRange() public pure {
        uint256 baseFee = 1e6; // 1% base fee

        // Test full interval [0, 1] normalized to BASIS_POINT_SCALE
        uint256 start = 0;
        uint256 end = 1e8; // BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 34000000, "Fee should be maximum for full range");
    }

    function test_CalculateQuadraticTotalFee_HalfRange() public pure {
        uint256 baseFee = 1e4; // 0.01% base fee

        // Test half-interval interval [0.5, 1] normalized to BASIS_POINT_SCALE
        uint256 start = 5e7;
        uint256 end = 1e8; // BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        assertEq(fee, 58337500, "Fee should be maximum for full range");
    }

    function test_Fuzz_CalculateQuadraticTotalFee(uint256 baseFee, uint256 start, uint256 end) public pure {
        // // Bound inputs to valid ranges
        vm.assume(baseFee > 0 && baseFee <= FeeMath.BASIS_POINT_SCALE);
        vm.assume(start >= 0 && start <= FeeMath.BASIS_POINT_SCALE);
        vm.assume(end > start && end <= FeeMath.BASIS_POINT_SCALE); // Ensure end >= start

        uint256 fee = FeeMath.calculateQuadraticTotalFee(baseFee, start, end);

        // Calculate expected fee using the quadratic formula:
        // expectedFee = ((1 - baseFee) * (end^3 - start^3)/3 + baseFee * (end - start)) / (end - start) * BASIS_POINT_SCALE
        // Calculate cubic terms separately with different order of operations
        uint256 scaledEnd = end * end * end;
        uint256 scaledStart = start * start * start;
        uint256 quadraticPortion = (FeeMath.BASIS_POINT_SCALE - baseFee) * (scaledEnd - scaledStart)
            / FeeMath.BASIS_POINT_SCALE / FeeMath.BASIS_POINT_SCALE / 3;
        uint256 expectedFee = quadraticPortion / (end - start) + baseFee;

        assertEq(fee, expectedFee, "Fee calculation mismatch");

        // Additional invariant checks
        assertLe(fee, FeeMath.BASIS_POINT_SCALE, "Fee exceeds max");
        assertGe(fee, baseFee, "Fee below base fee");
        if (start == end) {
            assertEq(fee, baseFee, "Fee should equal base fee when start == end");
        }
    }

    function test_Fuzz_QuadraticBufferFee(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailable,
        uint256 baseFee
    ) public pure {
        // Bound inputs to valid ranges
        vm.assume(bufferMaxSize >= 10 && bufferMaxSize <= 100000 ether);
        vm.assume(withdrawalAmount > 0 && withdrawalAmount <= bufferAvailable);
        vm.assume(bufferAvailable > 0 && bufferAvailable <= bufferMaxSize);
        vm.assume(baseFee > 0 && baseFee <= FeeMath.BASIS_POINT_SCALE / 2);

        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, baseFee, FeeMath.FeeType.OnRaw
        );

        // Calculate expected fee using equivalent formula:
        // If buffer available > flat portion threshold:
        //   fee = baseFee * withdrawalAmount
        // Else:
        //   fee = baseFee * withdrawalAmount * (1 + quadratic_multiplier)
        // Where quadratic_multiplier increases as buffer decreases
        uint256 bufferNonLinearAmount =
            (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;
        uint256 expectedFee;

        if (bufferAvailable > bufferNonLinearAmount) {
            // Linear portion
            if (bufferAvailable - withdrawalAmount >= bufferNonLinearAmount) {
                // Entirely in linear region
                expectedFee = withdrawalAmount * baseFee / BASIS_POINT_SCALE;
            } else {
                // Straddles linear and non-linear regions
                uint256 linearAmount = bufferAvailable - bufferNonLinearAmount;
                uint256 nonLinearAmount = withdrawalAmount - linearAmount;

                uint256 linearFee = linearAmount * baseFee / BASIS_POINT_SCALE;
                uint256 nonLinearFee = nonLinearAmount
                    * FeeMath.calculateQuadraticTotalFee(
                        baseFee, 0, nonLinearAmount * BASIS_POINT_SCALE / bufferNonLinearAmount
                    ) / BASIS_POINT_SCALE;

                expectedFee = linearFee + nonLinearFee;
            }
        } else {
            // Entirely in non-linear region
            uint256 start = bufferNonLinearAmount - bufferAvailable;
            uint256 end = start + withdrawalAmount;
            uint256 startScaled = start * BASIS_POINT_SCALE / bufferNonLinearAmount;
            uint256 endScaled = end * BASIS_POINT_SCALE / bufferNonLinearAmount;

            if (startScaled == endScaled) {
                endScaled = startScaled + 1; // create a 1 wei difference
            }
            expectedFee = withdrawalAmount * FeeMath.calculateQuadraticTotalFee(baseFee, startScaled, endScaled)
                / BASIS_POINT_SCALE;
        }

        assertApproxEqAbs(actualFee, expectedFee, 100, "Fee calculation mismatch");
        assertLe(actualFee, withdrawalAmount, "Fee cannot exceed withdrawal amount");
        assertGe(actualFee, withdrawalAmount * baseFee / BASIS_POINT_SCALE, "Fee cannot be less than base fee");
    }

    function test_Fuzz_QuadraticBufferFee_OnTotal(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailable,
        uint256 fee
    ) public pure {
        // Bound inputs to valid ranges
        vm.assume(bufferMaxSize >= 10 && bufferMaxSize <= 100000 ether);
        vm.assume(withdrawalAmount > 0 && withdrawalAmount <= bufferAvailable);
        vm.assume(bufferAvailable > 0 && bufferAvailable <= bufferMaxSize);
        vm.assume(fee > 0 && fee <= FeeMath.BASIS_POINT_SCALE / 2);

        // With low buffer, fee should be higher than linear fee
        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee, FeeMath.FeeType.OnTotal);
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount, bufferMaxSize, bufferAvailable, BUFFER_FEE_FLAT_PORTION, fee, FeeMath.FeeType.OnTotal
        );

        // Calculate expected fee using equivalent formula:
        // If buffer available > flat portion threshold:
        //   fee = baseFee * withdrawalAmount
        // Else:
        //   fee = baseFee * withdrawalAmount * (1 + quadratic_multiplier)
        // Where quadratic_multiplier increases as buffer decreases
        uint256 bufferNonLinearAmount =
            (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;
        uint256 expectedFee;

        if (bufferAvailable > bufferNonLinearAmount) {
            // Linear portion
            if (bufferAvailable - withdrawalAmount >= bufferNonLinearAmount) {
                // Entirely in linear region
                expectedFee = withdrawalAmount * fee / (fee + BASIS_POINT_SCALE);
            } else {
                // Straddles linear and non-linear regions
                uint256 linearAmount = bufferAvailable - bufferNonLinearAmount;
                uint256 nonLinearAmount = withdrawalAmount - linearAmount;

                uint256 linearFee = linearAmount * fee / (fee + BASIS_POINT_SCALE);
                uint256 quadraticFee = FeeMath.calculateQuadraticTotalFee(
                    fee, 0, nonLinearAmount * BASIS_POINT_SCALE / bufferNonLinearAmount
                );
                uint256 nonLinearFee = nonLinearAmount * quadraticFee / (quadraticFee + BASIS_POINT_SCALE);

                expectedFee = linearFee + nonLinearFee;
            }
        } else {
            // Entirely in non-linear region
            uint256 start = bufferNonLinearAmount - bufferAvailable;
            uint256 end = start + withdrawalAmount;
            uint256 startScaled = start * BASIS_POINT_SCALE / bufferNonLinearAmount;
            uint256 endScaled = end * BASIS_POINT_SCALE / bufferNonLinearAmount;

            if (startScaled == endScaled) {
                endScaled = startScaled + 1; // create a 1 wei difference
            }
            uint256 quadraticFee = FeeMath.calculateQuadraticTotalFee(fee, startScaled, endScaled);
            expectedFee = withdrawalAmount * quadraticFee / (quadraticFee + BASIS_POINT_SCALE);
        }

        assertApproxEqAbs(actualFee, expectedFee, 100, "Fee calculation mismatch");
        assertLe(actualFee, withdrawalAmount, "Fee cannot exceed withdrawal amount");
        assertGe(actualFee, withdrawalAmount * fee / (fee + BASIS_POINT_SCALE), "Fee cannot be less than base fee");
    }
}
