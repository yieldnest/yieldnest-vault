// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";

/*
    The Provider fetches state from other contracts.
*/

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

contract Provider is IProvider {
    error UnsupportedAsset(address asset);
    error RateIsNegative();

    address public immutable WUSDC;

    constructor(address _wusdc) {
        WUSDC = _wusdc;
    }

    function getRate(address asset) public view virtual returns (uint256) {
        if (asset == WUSDC) {
            return 1e18;
        }

        if (asset == MC.USDC) {
            return 1e18;
        }

        if (asset == MC.FLEX_STRATEGY_USDC) {
            // FLEX_STRATEGY_USDC has asset() = USDC, decimals() = 6
            // and USDC has decimals() = 6
            // Therefore to convert to WUSDC the rate conversion needs to be multiplied by 10**12
            // We do the multiplication first for higher precision, deriving the following:
            // IERC4626(MC.FLEX_STRATEGY_USDC).convertToAssets(1e6) * 10**12
            // ~= IERC4626(MC.FLEX_STRATEGY_USDC).convertToAssets(1e18)
            return IERC4626(MC.FLEX_STRATEGY_USDC).convertToAssets(1e18);
        }

        revert UnsupportedAsset(asset);
    }
}
