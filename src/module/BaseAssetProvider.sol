// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";

contract BaseAssetProvider is IProvider {
    error UnsupportedAsset(address asset);

    address public immutable baseAsset;
    address public immutable defaultAsset;
    uint256 public immutable baseAssetRate;
    uint256 public immutable defaultAssetRate;

    constructor(address _baseAsset, uint256 _baseAssetRate, address _defaultAsset, uint256 _defaultAssetRate) {
        baseAsset = _baseAsset;
        baseAssetRate = _baseAssetRate;
        defaultAsset = _defaultAsset;
        defaultAssetRate = _defaultAssetRate;
    }

    function getRate(address asset) public view returns (uint256) {
        if (asset == baseAsset) {
            return baseAssetRate;
        }

        if (asset == defaultAsset) {
            return defaultAssetRate;
        }

        revert UnsupportedAsset(asset);
    }
}
