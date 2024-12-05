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

    enum FeeType {
        OnRaw,
        OnTotal
    }

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
}
