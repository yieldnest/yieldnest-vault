// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";

contract MockProvider is Provider {
    mapping(address => uint256) private _mockRates;

    mapping(address => bool) private _erc4626;

    function setRate(address asset, uint256 rate_) external {
        _mockRates[asset] = rate_;
    }

    function getRate(address asset) public view override returns (uint256) {
        if (_erc4626[asset]) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        uint256 mockRate = _mockRates[asset];
        if (mockRate != 0) {
            return mockRate;
        }
        return super.getRate(asset);
    }

    function addERC4626(address asset) external {
        _erc4626[asset] = true;
    }
}
