// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SingleVault} from "src/SingleVault.sol";

contract MockSingleVault is SingleVault {
    constructor() {
        _disableInitializers();
    }

    uint256 public constant R_TWO_D = 2;
}
