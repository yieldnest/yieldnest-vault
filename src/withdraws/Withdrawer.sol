// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/base/BaseStrategy.sol";

import {AsyncWithdrawLib} from "src/libraries/AsyncWithdrawLib.sol";

contract Withdrawer is BaseStrategy {
    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        return AsyncWithdrawLib.computeTotalAssets();
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }
}
