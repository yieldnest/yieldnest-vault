// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {FeeMath} from "src/module/FeeMath.sol";

contract FeeMathTest is Test {
    uint256 constant BASIS_POINT_SCALE = 1e8;
    uint256 constant BUFFER_FEE_FLAT_PORTION = 8e7; // 80%
    uint256 constant QUADRATIC_A_FACTOR = 5e7; // 50%

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
        uint256 decimals = 18;

        // With full buffer, should just be linear fee
        uint256 expectedFee = FeeMath.linearFee(withdrawalAmount, fee);
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee,
            decimals
        );

        assertEq(actualFee, expectedFee, "Full buffer fee calculation incorrect");
    }

    function test_QuadraticBufferFee_LowBuffer() public {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 100 ether; // Low buffer
        uint256 fee = 1e4; // 0.01% fee
        uint256 decimals = 18;

        uint256 bufferNonLinearAmount = (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;
        
        // With low buffer, fee should be higher than linear fee
        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee);
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee,
            decimals
        );

        assertTrue(actualFee > linearFee, "Low buffer fee should be higher than linear fee");
    }

    function test_QuadraticBufferFee_ZeroBuffer() public {
        uint256 withdrawalAmount = 100 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 0; // Zero buffer
        uint256 fee = 1e4; // 0.01% fee
        uint256 decimals = 18;

        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee,
            decimals
        );

        uint256 linearFee = FeeMath.linearFee(withdrawalAmount, fee);
        assertTrue(actualFee > linearFee, "Zero buffer fee should be higher than linear fee");
    }

    function test_CalculateQuadraticTotalFee() public {
        uint256 A = QUADRATIC_A_FACTOR;
        uint256 baseFee = 1e4;
        uint256 start = 0;
        uint256 end = 100 ether;
        uint256 decimals = 18;

        uint256 fee = FeeMath.calculateQuadraticTotalFee(
            A,
            baseFee,
            start,
            end,
            decimals
        );

        assertTrue(fee > 0, "Quadratic fee should be greater than zero");
    }

    function test_QuadraticBufferFee_PartialNonLinear() public {
        uint256 withdrawalAmount = 350 ether;
        uint256 bufferMaxSize = 1000 ether;
        uint256 bufferAvailable = 400 ether; // Just above non-linear threshold
        uint256 fee = 1e4;
        uint256 decimals = 18;

        uint256 bufferNonLinearAmount = (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;
        uint256 linearPortion = bufferAvailable - bufferNonLinearAmount;
        
        uint256 actualFee = FeeMath.quadraticBufferFee(
            withdrawalAmount,
            bufferMaxSize,
            bufferAvailable,
            fee,
            decimals
        );

        uint256 linearOnlyFee = FeeMath.linearFee(withdrawalAmount, fee);
        assertGt(actualFee, linearOnlyFee, "Partial non-linear fee should be higher than pure linear fee");
    }
}
