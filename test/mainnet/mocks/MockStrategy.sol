// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseStrategy} from "src/strategy/BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external initializer {
        _initialize(
            admin,
            name,
            symbol,
            decimals_,
            false, // paused_ is always false for test MockStrategy
            countNativeAsset_,
            alwaysComputeTotalAssets_,
            defaultAssetIndex_
        );
        // No defaultAssetIndex_ parameter in _initialize(), remove extra argument
    }

    function _feeOnRaw(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256, address) public pure override returns (uint256) {
        return 0;
    }
}
