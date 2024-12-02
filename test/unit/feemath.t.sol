// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {console} from "lib/forge-std/src/console.sol";


contract FeeMathTest is Test {
    uint256 constant BASIS_POINT_SCALE = 1e8;
    uint256 constant BUFFER_FEE_FLAT_PORTION = 8e7; // 80%

    function test_LinearFee() public {
        uint256 amount = 1000 ether;
        uint256 fee = 1e4; // 0.01% fee

        uint256 expectedFee = (amount * fee) / BASIS_POINT_SCALE;
        uint256 actualFee = FeeMath.linearFee(amount, fee);

        assertEq(actualFee, expectedFee, "Linear fee calculation incorrect");
    }

    function test_QuadraticBufferFee_FullBuffer() public {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 1000 ether; // Full buffer
        uint256 fee = 1e4; // 0.01% fee

        // With full buffer, should just be linear fee
        uint256 expectedFee = (withdrawalAmount * fee) / BASIS_POINT_SCALE; // Calculate expected fee using same formula as linearFee()
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee
        );

        assertEq(actualFee, expectedFee, "Full buffer fee calculation incorrect");
    }

    function test_QuadraticBufferFee_LowBuffer() public {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 100 ether; // Low buffer
        uint256 fee = 1e4; // 0.01% fee
        
        // With low buffer, fee should be higher than linear fee
        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee);
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee
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

        vm.expectRevert(abi.encodeWithSelector(FeeMath.WithdrawalExceedsBuffer.selector, withdrawalAmount, bufferAvailable));
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee
        );

        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee);
    }

    function test_QuadraticBufferFee_PartialNonLinear() public {
        uint256 withdrawalAmount = 350 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 400 ether; // Just above non-linear threshold
        uint256 fee = 1e4;

        uint256 bufferNonLinearAmount = (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;
        uint256 linearPortion = bufferAvailable - bufferNonLinearAmount;
        
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee
        );

        uint256 linearOnlyFee = FeeMath.linearFee(withdrawalAmount, fee);
        assertGt(actualFee, linearOnlyFee, "Partial non-linear fee should be higher than pure linear fee");
    }

    function test_CalculateQuadraticTotalFee_PartialBuffer() public {
        uint256 baseFee = 1e6; // 1% base fee
        
        // Test interval [0.4, 0.6] normalized to BASIS_POINT_SCALE
        uint256 start = 4e7; // 0.4 * BASIS_POINT_SCALE 
        uint256 end = 6e7;   // 0.6 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start, 
            end
        );

        assertEq(fee, 26080000, "Fee should equal expected");
    }

    function test_CalculateQuadraticTotalFee_LowBuffer() public {
        uint256 baseFee = 1e6; // 1% base fee
        
        // Test interval [0.1, 0.2] normalized to BASIS_POINT_SCALE
        uint256 start = 1e7; // 0.1 * BASIS_POINT_SCALE
        uint256 end = 2e7;   // 0.2 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start,
            end
        );

        assertEq(fee, 3310000, "Fee should be higher in low buffer region");
    }

    function test_CalculateQuadraticTotalFee_HighBuffer() public {
        uint256 baseFee = 1e6; // 1% base fee
        
        // Test interval [0.8, 0.9] normalized to BASIS_POINT_SCALE
        uint256 start = 8e7; // 0.8 * BASIS_POINT_SCALE
        uint256 end = 9e7;   // 0.9 * BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start,
            end
        );

        assertEq(fee, 72610000, "Fee should be much higher in high buffer region");
    }

    function test_CalculateQuadraticTotalFee_FullRange() public {
        uint256 baseFee = 1e6; // 1% base fee
        
        // Test full interval [0, 1] normalized to BASIS_POINT_SCALE
        uint256 start = 0;
        uint256 end = 1e8;   // BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start,
            end
        );

        assertEq(fee, 34000000, "Fee should be maximum for full range");
    }


    function test_CalculateQuadraticTotalFee_HalfRange() public {
        uint256 baseFee = 1e4; // 0.01% base fee
        
        // Test half-interval interval [0.5, 1] normalized to BASIS_POINT_SCALE
        uint256 start = 5e7;
        uint256 end = 1e8;   // BASIS_POINT_SCALE

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start,
            end
        );

        assertEq(fee, 58337500, "Fee should be maximum for full range");
    }

    function test_Fuzz_CalculateQuadraticTotalFee(
        uint256 baseFee,
        uint256 start,
        uint256 end
    ) public {


        // // Bound inputs to valid ranges
        vm.assume(baseFee > 0 && baseFee <= FeeMath.BASIS_POINT_SCALE);
        vm.assume(start >= 0 && start <= FeeMath.BASIS_POINT_SCALE);
        vm.assume(end > start && end <= FeeMath.BASIS_POINT_SCALE); // Ensure end >= start
        
        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            baseFee,
            start,
            end
        );

        // Calculate expected fee using the quadratic formula:
        // expectedFee = ((1 - baseFee) * (end^3 - start^3)/3 + baseFee * (end - start)) / (end - start) * BASIS_POINT_SCALE
        // Calculate cubic terms separately with different order of operations
        uint256 scaledEnd = end * end * end;
        uint256 scaledStart = start * start * start;
        uint256 quadraticPortion = (FeeMath.BASIS_POINT_SCALE - baseFee) * (scaledEnd - scaledStart) / FeeMath.BASIS_POINT_SCALE / FeeMath.BASIS_POINT_SCALE / 3;
        uint256 expectedFee = quadraticPortion / (end - start) + baseFee;

        // assertEq(fee, expectedFee, "Fee calculation mismatch");
        
        // Additional invariant checks
        assertLe(fee, FeeMath.BASIS_POINT_SCALE, "Fee exceeds max");
        assertGe(fee, baseFee, "Fee below base fee");
        if (start == end) {
            assertEq(fee, baseFee, "Fee should equal base fee when start == end");
        }
    }
}
