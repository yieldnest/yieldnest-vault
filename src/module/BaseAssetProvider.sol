// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";

contract BaseAssetProvider is IProvider {
    error UnsupportedAsset(address asset);

    address public immutable baseAsset;

    constructor(address _baseAsset) {
        baseAsset = _baseAsset;
    }

    function getRate(address asset) public view returns (uint256) {
        if (asset == baseAsset) {
            return 1e18;
        }

        revert UnsupportedAsset(asset);
    }
}
