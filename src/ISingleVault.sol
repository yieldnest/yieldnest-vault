// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, IERC4626, IAccessControl} from "src/Common.sol";

interface ISingleVault is IERC20, IERC4626, IAccessControl {
    error AssetZeroAddress();
    error NameEmpty();
    error SymbolEmpty();
    error AdminZeroAddress();
    error ProposersEmpty();
    error ExecutorsEmpty();

    function initialize(
        IERC20 asset_,
        string calldata name_,
        string calldata symbol_,
        address admin_,
        uint256 minDelay_,
        address[] calldata proposers_,
        address[] calldata executors_
    ) external;
}
