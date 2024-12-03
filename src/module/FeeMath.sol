// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {Math} from "src/Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Guard} from "src/module/Guard.sol";

library FeeMath {
    enum FeeType {
        OnRaw,
        OnTotal
    }

    using Math for uint256;

    error AmountExceedsScale();
    error BufferExceedsMax(uint256 bufferAvailable, uint256 bufferMax);
    error WithdrawalExceedsBuffer(uint256 withdrawalAmount, uint256 bufferAvailable);
    error StartMustBeLessThanEnd(uint256 start, uint256 end);
    error UnsupportedFeeType(FeeType feeType);

    uint256 public constant BASIS_POINT_SCALE = 1e8;

    function linearFee(uint256 amount, uint256 fee, FeeType feeType) internal pure returns (uint256) {
        if (feeType == FeeType.OnRaw) {
            return feeOnRaw(amount, fee);
        } else if (feeType == FeeType.OnTotal) {
            return feeOnTotal(amount, fee);
        } else {
            revert UnsupportedFeeType(feeType);
        }
    }

    function feeOnRaw(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return amount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    function feeOnTotal(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return amount.mulDiv(fee, fee + BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

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
        FeeType feeType
    ) internal pure returns (uint256) {
        if (fee > BASIS_POINT_SCALE) {
            revert AmountExceedsScale();
        }

        if (bufferAvailableAmount > bufferMaxSize) {
            revert BufferExceedsMax(bufferAvailableAmount, bufferMaxSize);
        }

        if (withdrawalAmount > bufferAvailableAmount) {
            revert WithdrawalExceedsBuffer(withdrawalAmount, bufferAvailableAmount);
        }

        uint256 bufferNonLinearAmount = (BASIS_POINT_SCALE - bufferFlatFeeFraction) * bufferMaxSize / BASIS_POINT_SCALE;

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

            uint256 nonLinearStartScaled = nonLinearStart * BASIS_POINT_SCALE / bufferNonLinearAmount;

            uint256 nonLinearEndScaled = nonLinearEnd * BASIS_POINT_SCALE / bufferNonLinearAmount;

            if (nonLinearEndScaled == nonLinearStartScaled) {
                nonLinearEndScaled = nonLinearStartScaled + 1 wei;
            }

            nonLinearFee = calculateQuadraticTotalFee(fee, nonLinearStartScaled, nonLinearEndScaled);
        }

        // Return fee based on type
        if (feeType == FeeType.OnRaw) {
            return feeOnRaw(linearFeeTaxedAmount, fee) + feeOnRaw(nonLinearFeeTaxedAmount, nonLinearFee);
        } else if (feeType == FeeType.OnTotal) {
            return feeOnTotal(linearFeeTaxedAmount, fee) + feeOnTotal(nonLinearFeeTaxedAmount, nonLinearFee);
        } else {
            revert UnsupportedFeeType(feeType);
        }
    }

    function calculateQuadraticTotalFee(uint256 baseFee, uint256 start, uint256 end) public pure returns (uint256) {
        if (start >= end) {
            revert StartMustBeLessThanEnd(start, end);
        }

        if (start > BASIS_POINT_SCALE || end > BASIS_POINT_SCALE || baseFee > BASIS_POINT_SCALE) {
            revert AmountExceedsScale();
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

        uint256 end3 = (BASIS_POINT_SCALE - baseFee) * end * end * end / BASIS_POINT_SCALE / BASIS_POINT_SCALE;
        uint256 start3 = (BASIS_POINT_SCALE - baseFee) * start * start * start / BASIS_POINT_SCALE / BASIS_POINT_SCALE;

        // The division by 3 comes from integrating x^2 to get x^3/3
        // The division by (end-start) normalizes the integral over the interval
        uint256 totalFee = ((end3 - start3) / 3) / (end - start) + baseFee;

        return totalFee; // adjusted to BASIS_POINT_SCALE
    }
}
