// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626, IERC20Metadata} from "src/Common.sol";
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
    error InvalidStrategy(address strategy, address strategyAsset, uint8 strategyDecimals);

    address public immutable WUSDC;
    address public immutable STRATEGY;

    constructor(address _wusdc, address _strategy) {
        address strategyAsset = IERC4626(_strategy).asset();
        uint8 strategyDecimals = IERC20Metadata(_strategy).decimals();

        // getRate assumes convertToAssets(1e18) yields an 18-decimal rate, which holds only for
        // 6-decimal strategies over 6-decimal stables or 18-decimal strategies over 18-decimal stables
        bool valid6Decimals = (strategyAsset == MC.USDC || strategyAsset == MC.USDT) && strategyDecimals == 6;
        bool valid18Decimals = (strategyAsset == MC.USDS || strategyAsset == MC.USDE) && strategyDecimals == 18;

        if (!valid6Decimals && !valid18Decimals) {
            revert InvalidStrategy(_strategy, strategyAsset, strategyDecimals);
        }

        WUSDC = _wusdc;
        STRATEGY = _strategy;
    }

    function getRate(address asset) public view virtual returns (uint256) {
        if (asset == WUSDC) {
            return 1e18;
        }

        if (asset == MC.USDC) {
            return 1e18;
        }

        if (asset == STRATEGY) {
            // STRATEGY has asset() = USDC, decimals() = 6
            // and USDC has decimals() = 6
            // Therefore to convert to WUSDC the rate conversion needs to be multiplied by 10**12
            // We do the multiplication first for higher precision, deriving the following:
            // IERC4626(STRATEGY).convertToAssets(1e6) * 10**12
            // ~= IERC4626(STRATEGY).convertToAssets(1e18)
            return IERC4626(STRATEGY).convertToAssets(1e18);
        }

        revert UnsupportedAsset(asset);
    }
}
