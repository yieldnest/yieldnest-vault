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
                linearFeeTaxedAmount = bufferAvailableAmount - bufferAvailableAmount;
                nonLinearFeeTaxedAmount = withdrawalAmount - linearFeeTaxedAmount;
            }
        } else {
            nonLinearFeeTaxedAmount = withdrawalAmount;
        }

        return linearFee(linearFeeTaxedAmount, fee); // TODO: add non linear component
    }
}
