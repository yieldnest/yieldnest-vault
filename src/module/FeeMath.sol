// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {Math} from "src/Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Guard} from "src/module/Guard.sol";
import {console} from "lib/forge-std/src/console.sol";

library FeeMath {
    using Math for uint256;

    uint256 public constant BASIS_POINT_SCALE = 1e8;

    uint256 public constant BUFFER_FEE_FLAT_PORTION = 8e7; // 80%

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
    |                         Quadratic portion      baseFee (e.g. 0.01%)
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
        
    Fee increases quadratically from baseFee up to 100% as buffer decreases below threshold
    */
    function quadraticBufferFee(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailableAmount,
        uint256 fee
    ) internal view returns (uint256) {
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
        uint256 nonLinearFee = 0;
        if (nonLinearFeeTaxedAmount > 0) {
            uint256 nonLinearStart
                = bufferAvailableAmount >= bufferNonLinearAmount ? 0 : bufferNonLinearAmount - bufferAvailableAmount;

            uint256 nonLinearStartScaled = nonLinearStart * BASIS_POINT_SCALE / bufferNonLinearAmount;

            uint256 nonLinearEnd
                = bufferAvailableAmount >= bufferNonLinearAmount ? nonLinearFeeTaxedAmount : nonLinearStart + withdrawalAmount;

            uint256 nonLinearEndScaled = nonLinearEnd * BASIS_POINT_SCALE / bufferNonLinearAmount;

            console.log("nonLinearStartScaled:", nonLinearStartScaled);
            console.log("nonLinearEndScaled:", nonLinearEndScaled);
            console.log("fee:", fee);
            console.log("bufferMaxSize:", bufferMaxSize);

            nonLinearFee = calculateQuadraticTotalFee(
                fee,
                nonLinearStartScaled,
                nonLinearEndScaled
            );
        }

        return linearFeeAmount + nonLinearFee * nonLinearFeeTaxedAmount / BASIS_POINT_SCALE;
    }

    function calculateQuadraticTotalFee(
        uint256 baseFee,
        uint256 start,
        uint256 end
        ) public pure returns (uint256) {
        // Calculate end^3 and start^3
        uint256 end3 = end * end * end / BASIS_POINT_SCALE / BASIS_POINT_SCALE;
        uint256 start3 = start * start * start / BASIS_POINT_SCALE / BASIS_POINT_SCALE;

        // Calculate the total fee
        uint256 totalFee = ((BASIS_POINT_SCALE - baseFee) * (end3 - start3) / 3 + baseFee * (end - start)) / BASIS_POINT_SCALE;

        return totalFee; // adjusted to BASIS_POINT_SCALE
    }
}
