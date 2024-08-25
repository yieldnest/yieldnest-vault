// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

contract PoleVault is ERC4626 {
    // Constructor to initialize the ERC4626 contract
    constructor(IERC20 asset) ERC4626(asset) {
        // Additional initialization if needed
    }

    // ... existing code ...
}