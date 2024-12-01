// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

import {Math} from "src/Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Guard} from "src/module/Guard.sol";

library Fee {
    using Math for uint256;

    uint256 public constant BASIS_POINT_SCALE = 1e8;

    uint256 public constant BUFFER_FEE_FLAT_PORTION = 8e7;

    uint256 public constant QUADRATIC_B_FACTOR = 2;

    function linearFee(uint256 amount, uint256 fee) internal pure returns (uint256) {
        return amount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    // <----|--X---------------->
    // <--|~~~~|---------------->

    function quadraticBufferFee(
        uint256 withdrawalAmount,
        uint256 bufferMaxSize,
        uint256 bufferAvailableAmount,
        uint256 fee
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
            uint256 nonLinearStart = bufferNonLinearAmount - bufferAvailableAmount + nonLinearFeeTaxedAmount;
            nonLinearFeeAmount = QUADRATIC_A_FACTOR * nonLinearStart * nonLinearStart +
                                 QUADRATIC_B_FACTOR * nonLinearStart;
            nonLinearFeeAmount = nonLinearFeeAmount.mulDiv(fee, BASIS_POINT_SCALE, Math.Rounding.Ceil);
        }

        return linearFeeAmount + nonLinearFeeAmount;
    }

    function calculateTotalFee(uint256 A, uint256 baseFee, uint256 start, uint256 end) public pure returns (uint256) {
        // Calculate end^3 and start^3
        uint256 F3 = end * end * end;
        uint256 S3 = start * start * start;

        // Calculate the total fee
        uint256 totalFee = (A * (F3 - S3)) / 3 + BaseFee * (end - start);

        return totalFee;
    }
    }
}
