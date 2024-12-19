// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Math} from "src/Common.sol";
import {FeeMath} from "src/module/FeeMath.sol";

library FeeMathPoly {
    using Math for uint256;

    /**
     *
     *                                                                           *
     *                                EXPERIMENTAL                                *
     *                                                                           *
     *
     */

    /// @notice EXPERIMENTAL - DO NOT USE IN PRODUCTION. DO NOT AUDIT the code below.
    /// @dev The fee calculations (quadraticBufferFee, calculateQuadraticTotalFee)
    ///      are experimental and have not been audited.
    ///      They are subject to change without notice and may contain critical bugs.
    ///      Using these functions could result in loss of funds.
    /// @dev These fee calculations are experimental and have not been audited.
    ///      Use at your own risk. Subject to change.

    /*
    Fee Rate
    ^
    | 100% ....
    |          ....
    |               ....
    |                    ....
    |                         ..... 
    |                              _________________ Linear portion (high buffer)
    |                         Quadratic portion      baseFee (e.g. 0.1%)
    |                     (low buffer region)
    +---------------------------------> Buffer Available
                                       (increases →)
    
    Formula:
    For linear portion (buffer > bufferNonLinearAmount):
        fee = amount * baseFee
    
    For quadratic portion (buffer <= bufferNonLinearAmount):
        fee = ∫(ax² + baseFee)dx from start to end
        where:
        - a = (1 - fee)
        - start = max(0, bufferNonLinearAmount - bufferAvailable) 
        - end = start + withdrawalAmount

        Solving the integral:
        fee = [ax³/3 + baseFee*x]|start to end
        fee = (a*end³/3 + baseFee*end) - (a*start³/3 + baseFee*start)
        fee = a*(end³ - start³)/3 + baseFee*(end - start)
        
        This is implemented in calculateQuadraticTotalFee() where:
        - Values are normalized to BASIS_POINT_SCALE
        - start and end are the x-coordinates scaled to BASIS_POINT_SCALE
        - baseFee is the linear fee rate
    Fee increases quadratically from baseFee up to 100% as buffer decreases below threshold
    */
    function quadraticBufferFee(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailableAmount,
        uint256 bufferFlatFeeFraction,
        uint256 fee,
        FeeMath.FeeType feeType
    ) internal pure returns (uint256) {
        if (fee > FeeMath.BASIS_POINT_SCALE) {
            revert FeeMath.AmountExceedsScale();
        }

        if (bufferAvailableAmount > bufferMaxSize) {
            revert FeeMath.BufferExceedsMax(bufferAvailableAmount, bufferMaxSize);
        }

        if (withdrawalAmount > bufferAvailableAmount) {
            revert FeeMath.WithdrawalExceedsBuffer(withdrawalAmount, bufferAvailableAmount);
        }

        uint256 bufferNonLinearAmount =
            (FeeMath.BASIS_POINT_SCALE - bufferFlatFeeFraction) * bufferMaxSize / FeeMath.BASIS_POINT_SCALE;

        uint256 linearFeeTaxedAmount = 0;
        uint256 nonLinearFeeTaxedAmount = 0;
        if (bufferAvailableAmount > bufferNonLinearAmount) {
            if (bufferAvailableAmount - withdrawalAmount >= bufferNonLinearAmount) {
                // the entire withdrawalAmount is applied the linear fee in this case
                linearFeeTaxedAmount = withdrawalAmount;
            } else {
                // in case bufferAvailableAmount - withdrawalAmount < bufferNonLinearAmount
                // what is in excess of the bufferNonLinearAmount is applied a linear fee
                linearFeeTaxedAmount = bufferAvailableAmount - bufferNonLinearAmount;
                // what remains of the withdrawalAmount is a applied the nonLinearFee
                nonLinearFeeTaxedAmount = withdrawalAmount - linearFeeTaxedAmount;
            }
        } else {
            // in case bufferAvailableAmount <= bufferNonLinearAmount
            // the entire withdrawalAmount is applied the nonlinear fee
            nonLinearFeeTaxedAmount = withdrawalAmount;
        }

        // Calculate the non-linear fee using a quadratic function
        uint256 nonLinearFee = 0;
        if (nonLinearFeeTaxedAmount > 0) {
            uint256 nonLinearStart;
            uint256 nonLinearEnd;

            // Case 1: When linearFeeTaxedAmount > 0
            // This means we're straddling the threshold between linear and non-linear regions
            // Buffer:  [----linear----|----nonlinear----]
            // Amount:           [withdrawal]
            //                   ^        ^
            //              start=0   end=nonLinearFeeTaxedAmount
            if (linearFeeTaxedAmount > 0) {
                nonLinearStart = 0;
                nonLinearEnd = nonLinearFeeTaxedAmount;
            }
            // Case 2: When linearFeeTaxedAmount = 0
            // This means we're fully in the non-linear region
            // Buffer:  [----linear----|----nonlinear----]
            // Amount:                      [withdrawal]
            //                              ^     ^
            //                           start   end
            else {
                nonLinearStart = bufferNonLinearAmount - bufferAvailableAmount;
                nonLinearEnd = nonLinearStart + withdrawalAmount;
            }

            uint256 nonLinearStartScaled = nonLinearStart * FeeMath.BASIS_POINT_SCALE / bufferNonLinearAmount;

            uint256 nonLinearEndScaled = nonLinearEnd * FeeMath.BASIS_POINT_SCALE / bufferNonLinearAmount;

            if (nonLinearEndScaled == nonLinearStartScaled) {
                nonLinearEndScaled = nonLinearStartScaled + 1 wei;
            }

            nonLinearFee = calculateQuadraticTotalFee(fee, nonLinearStartScaled, nonLinearEndScaled);
        }

        // Return fee based on type
        if (feeType == FeeMath.FeeType.OnRaw) {
            return FeeMath.feeOnRaw(linearFeeTaxedAmount, fee) + FeeMath.feeOnRaw(nonLinearFeeTaxedAmount, nonLinearFee);
        } else if (feeType == FeeMath.FeeType.OnTotal) {
            return FeeMath.feeOnTotal(linearFeeTaxedAmount, fee)
                + FeeMath.feeOnTotal(nonLinearFeeTaxedAmount, nonLinearFee);
        } else {
            revert FeeMath.UnsupportedFeeType(feeType);
        }
    }

    function calculateQuadraticTotalFee(uint256 baseFee, uint256 start, uint256 end) public pure returns (uint256) {
        if (start >= end) {
            revert FeeMath.StartMustBeLessThanEnd(start, end);
        }

        if (start > FeeMath.BASIS_POINT_SCALE || end > FeeMath.BASIS_POINT_SCALE || baseFee > FeeMath.BASIS_POINT_SCALE)
        {
            revert FeeMath.AmountExceedsScale();
        }

        // The original formula is:
        // fee = ((1 - baseFee) * ((end / BASIS_POINT_SCALE)^3 - (start / BASIS_POINT_SCALE)^3)/3 + baseFee * ((end / BASIS_POINT_SCALE) - (start / BASIS_POINT_SCALE))) / (end  - start) * BASIS_POINT_SCALE
        //
        // Step 1: Factor out (1-baseFee) from first term
        // fee = (1-baseFee) * ((end / BASIS_POINT_SCALE)^3 - (start / BASIS_POINT_SCALE)^3)/3 / (end-start) * BASIS_POINT_SCALE
        //       + baseFee * ((end / BASIS_POINT_SCALE) - (start / BASIS_POINT_SCALE)) / (end-start) * BASIS_POINT_SCALE
        //
        // Step 2: Simplify second term - the division by (end-start) cancels out, multiplication by BASIS_POINT_SCALE cancels out
        // fee = (1-baseFee) * ((end / BASIS_POINT_SCALE)^3 - (start / BASIS_POINT_SCALE)^3)/3 / (end-start) * BASIS_POINT_SCALE
        //       + baseFee
        //
        // Step 3: Delay division by BASIS_POINT_SCALE in first term to maximize precision
        // fee = (1-baseFee) * (end^3 - start^3) / BASIS_POINT_SCALE / BASIS_POINT_SCALE / 3 / (end-start)
        //       + baseFee

        uint256 end3 = (FeeMath.BASIS_POINT_SCALE - baseFee) * end * end * end / FeeMath.BASIS_POINT_SCALE
            / FeeMath.BASIS_POINT_SCALE;
        uint256 start3 = (FeeMath.BASIS_POINT_SCALE - baseFee) * start * start * start / FeeMath.BASIS_POINT_SCALE
            / FeeMath.BASIS_POINT_SCALE;

        // The division by 3 comes from integrating x^2 to get x^3/3
        // The division by (end-start) normalizes the integral over the interval
        uint256 totalFee = ((end3 - start3) / 3) / (end - start) + baseFee;

        return totalFee; // adjusted to BASIS_POINT_SCALE
    }
}
