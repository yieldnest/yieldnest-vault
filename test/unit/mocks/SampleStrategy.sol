// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";

/// @dev Minimal concrete BaseStrategy used to measure inherited bytecode headroom.
contract SampleStrategy is BaseStrategy {
    function initialize(address admin, string memory name, string memory symbol) external initializer {
        _initialize(admin, name, symbol, 18, false, false, false, 0);
    }

    function _feeOnRaw(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256, address) public pure override returns (uint256) {
        return 0;
    }
}
