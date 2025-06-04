// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ISuperUSDC is IERC4626 {
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss)
        external
        returns (uint256 assets);
}
