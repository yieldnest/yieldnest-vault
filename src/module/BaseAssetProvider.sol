// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";

contract BaseAssetProvider is IProvider {
    error UnsupportedAsset(address asset);

    address public immutable baseAsset;
    uint256 public immutable rate;

    constructor(address _baseAsset, uint256 _rate) {
        baseAsset = _baseAsset;
        rate = _rate;
    }

    function getRate(address asset) public view returns (uint256) {
        if (asset == baseAsset) {
            return rate;
        }

        revert UnsupportedAsset(asset);
    }
}
