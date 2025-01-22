// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Strategy} from "src/Strategy.sol";

contract ynETHxLPStrategy is Strategy {

    // function _convertToAssets(uint256 shares) internal view override returns (uint256 assets) {
    //     assets = shares * IERC4626(MC.YNLSDE).convertToAssets(1e18) / IERC4626(MC.YNETH).convertToAssets(1e18);
    // }
    // function _convertToShares(uint256 assets) internal view override returns (uint256 shares) {
    //     shares = assets * IERC4626(MC.YNETH).convertToAssets(1e18) / IERC4626(MC.YNLSDE).convertToAssets(1e18);
    // }
}
