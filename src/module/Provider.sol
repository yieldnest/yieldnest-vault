// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    IProvider,
    IStETH,
    IMETH,
    IsfrxETH,
    IRETH,
    IswETH,
    IFrxEthWethDualOracle,
    IynLSDe,
    ICurveLpConnector
} from "src/interface/IProvider.sol";
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

        revert UnsupportedAsset(asset);
    }
}
