// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockProvider is IProvider {
    using Math for uint256;

    mapping(address => uint256) private _mockRates;

    mapping(address => bool) private _erc4626;

    function setRate(address asset, uint256 rate_) external {
        _mockRates[asset] = rate_;
    }

    function getRate(address asset) public view override returns (uint256) {
        if (_erc4626[asset]) {
            uint256 assetsInUnderlying = IERC4626(asset).convertToAssets(1e18);
            address underlying = IERC4626(asset).asset();
            uint256 underlyingRate = getRate(underlying);
            return assetsInUnderlying.mulDiv(underlyingRate, 1e18);
        }

        uint256 mockRate = _mockRates[asset];
        if (mockRate != 0) {
            return mockRate;
        }
    }

    function addERC4626(address asset) external {
        _erc4626[asset] = true;
    }
}
