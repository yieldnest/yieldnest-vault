// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {Math} from "src/Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Guard} from "src/module/Guard.sol";
import {console} from "forge-std/console.sol";

library FeeMath {
    using Math for uint256;

    error AmountExceedsScale();
    error BufferExceedsMax(uint256 bufferAvailable, uint256 bufferMax);
    error WithdrawalExceedsBuffer(uint256 withdrawalAmount, uint256 bufferAvailable);
    error StartMustBeLessThanEnd(uint256 start, uint256 end);

    uint256 public constant BASIS_POINT_SCALE = 1e8;

    function linearFee(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return amount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
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
        uint256 fee
    ) internal view returns (uint256) {
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
                linearFeeTaxedAmount = withdrawalAmount;
            } else {
                linearFeeTaxedAmount = bufferAvailableAmount - bufferNonLinearAmount;
                nonLinearFeeTaxedAmount = withdrawalAmount - linearFeeTaxedAmount;
            }
        } else {
            nonLinearFeeTaxedAmount = withdrawalAmount;
        }

        uint256 linearFeeAmount = linearFee(linearFeeTaxedAmount, fee);

        // Calculate the non-linear fee using a quadratic function
        uint256 nonLinearFee = 0;
        if (nonLinearFeeTaxedAmount > 0) {
            uint256 nonLinearStart =
                bufferAvailableAmount >= bufferNonLinearAmount ? 0 : bufferNonLinearAmount - bufferAvailableAmount;

            uint256 nonLinearStartScaled = nonLinearStart * BASIS_POINT_SCALE / bufferNonLinearAmount;

            uint256 nonLinearEnd = bufferAvailableAmount >= bufferNonLinearAmount
                ? nonLinearFeeTaxedAmount
                : nonLinearStart + withdrawalAmount;

            uint256 nonLinearEndScaled = nonLinearEnd * BASIS_POINT_SCALE / bufferNonLinearAmount;

            nonLinearFee = calculateQuadraticTotalFee(fee, nonLinearStartScaled, nonLinearEndScaled);
        }

        return linearFeeAmount + nonLinearFee * nonLinearFeeTaxedAmount / BASIS_POINT_SCALE;
    }

    function calculateQuadraticTotalFee(uint256 baseFee, uint256 start, uint256 end) public pure returns (uint256) {
        if (start >= end) {
            revert StartMustBeLessThanEnd(start, end);
        }

        if (start > BASIS_POINT_SCALE || end > BASIS_POINT_SCALE || baseFee > BASIS_POINT_SCALE) {
            revert AmountExceedsScale();
        }

        // Calculate end^3 and start^3
        uint256 end3 = (BASIS_POINT_SCALE - baseFee) * end * end * end / BASIS_POINT_SCALE / BASIS_POINT_SCALE;
        uint256 start3 = (BASIS_POINT_SCALE - baseFee) * start * start * start / BASIS_POINT_SCALE / BASIS_POINT_SCALE;

        /* compute integral between End and Start */

        // Calculate the total fee
        uint256 totalFee = ((end3 - start3) / 3) / (end - start) + baseFee;

        return totalFee; // adjusted to BASIS_POINT_SCALE
    }
}
