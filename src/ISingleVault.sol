// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, IERC4626, IAccessControl} from "src/Common.sol";

interface ISingleVault is IERC20, IERC4626, IAccessControl {
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address operator_,
        uint256 minDelay_,
        address[] calldata proposers_,
        address[] calldata executors_
    ) external;
}
