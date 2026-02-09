// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";

contract MockStrategy is BaseStrategy {
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external initializer {
        _initialize(admin, name, symbol, 18, false, true, alwaysComputeTotalAssets_, defaultAssetIndex_);
    }

    function _feeOnRaw(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256, address) public pure override returns (uint256) {
        return 0;
    }
}
