// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {Math} from "src/Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Guard} from "src/module/Guard.sol";

library FeeMath {
    using Math for uint256;

    uint256 public constant BASIS_POINT_SCALE = 1e8;

    uint256 public constant BUFFER_FEE_FLAT_PORTION = 8e7;

    uint256 public constant QUADRATIC_A_FACTOR = 5e7;

    function linearFee(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return amount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }


    /*
    Fee Rate
    ^
    |    ....
    |       ....
    |           ....
    |               ....
    |                   ..... 
    |                        _________________ Linear portion (high buffer)
    |                   Quadratic portion
    |                (low buffer region)
    +---------------------------------> Buffer Available
                                       (increases →)
    
    Formula:
    For linear portion (buffer > bufferNonLinearAmount):
        fee = amount * baseFee
    
    For quadratic portion (buffer <= bufferNonLinearAmount): 
        fee = ∫(ax² + baseFee)dx from start to end
        where:
        - a = QUADRATIC_A_FACTOR 
        - start = max(0, bufferNonLinearAmount - bufferAvailable)
        - end = start + withdrawalAmount
        
    Fee increases quadratically as buffer decreases below threshold
    */
    function quadraticBufferFee(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailableAmount,
        uint256 fee,
        uint256 amountDecimals
    ) internal pure returns (uint256) {
        uint256 bufferNonLinearAmount =
            (BASIS_POINT_SCALE - BUFFER_FEE_FLAT_PORTION) * bufferMaxSize / BASIS_POINT_SCALE;

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
        uint256 nonLinearFeeAmount = 0;
        if (nonLinearFeeTaxedAmount > 0) {
            uint256 nonLinearStart
                = bufferAvailableAmount >= bufferNonLinearAmount ? 0 : bufferNonLinearAmount - bufferAvailableAmount;

            uint256 nonLinearEnd
                = bufferAvailableAmount >= bufferNonLinearAmount ? nonLinearFeeTaxedAmount : nonLinearStart + withdrawalAmount;

            nonLinearFeeAmount = calculateQuadraticTotalFee(
                QUADRATIC_A_FACTOR,
                fee,
                nonLinearStart,
                nonLinearEnd,
                amountDecimals
            );
            nonLinearFeeAmount = nonLinearFeeAmount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
        }

        return linearFeeAmount + nonLinearFeeAmount;
    }

    function calculateQuadraticTotalFee(
        uint256 A,
        uint256 baseFee,
        uint256 start,
        uint256 end,
        uint256 amountDecimals
        ) public pure returns (uint256) {
        uint256 unit = 10 ** amountDecimals;
        // Calculate end^3 and start^3
        uint256 end3 = end * end * end / unit / unit;
        uint256 start3 = start * start * start / unit / unit;

        // Calculate the total fee
        uint256 totalFee = (A * (end3 - start3) / BASIS_POINT_SCALE) / 3 + baseFee * (end - start);

        return totalFee;
    }
}
