// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IStrategy} from "src/interface/IStrategy.sol";
import {IERC20, ERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract MockClisBnbStrategy {
    /// @notice The version of the strategy contract.
    string public constant STRATEGY_VERSION = "0.2.0";

    function asset() public pure returns (address) {
        return MC.SLISBNB;
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares * 1.01 ether / 1e18;
    }
}
