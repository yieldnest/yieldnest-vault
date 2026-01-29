// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {IERC4626} from "src/Common.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockProvider is Provider {
    using Math for uint256;

    struct MockRate {
        uint256 rate;
        bool isZero;
    }

    mapping(address => MockRate) private _mockRates;

    mapping(address => bool) private _erc4626;

    function setRate(address asset, uint256 rate_) external {
        _mockRates[asset] = MockRate({rate: rate_, isZero: false});
    }

    function setZeroRate(address asset) external {
        _mockRates[asset] = MockRate({rate: 0, isZero: true});
    }

    function getRate(address asset) public view override returns (uint256) {
        if (_erc4626[asset]) {
            uint256 assetsInUnderlying = IERC4626(asset).convertToAssets(1e18);
            address underlying = IERC4626(asset).asset();
            uint256 underlyingRate = getRate(underlying);
            return assetsInUnderlying.mulDiv(underlyingRate, 1e18);
        }

        MockRate memory mockRate = _mockRates[asset];
        if (mockRate.rate != 0 || mockRate.isZero) {
            return mockRate.rate;
        }
        return super.getRate(asset);
    }

    function addERC4626(address asset) external {
        _erc4626[asset] = true;
    }
}
