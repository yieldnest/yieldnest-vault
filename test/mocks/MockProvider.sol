// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";
import {Provider} from "src/module/Provider.sol";

/*
    The Provider fetches state from other contracts.
*/

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

// contract MockProvider is Provider {
//     address public wrappedUSDC;

//     constructor(address _wrappedUSDC) {
//         wrappedUSDC = _wrappedUSDC;
//     }

//     function getRate(address asset) public view virtual override returns (uint256) {
//         if (asset == wrappedUSDC) {
//             return 1e18;
//         }

//         return super.getRate(asset);
//     }
// }
