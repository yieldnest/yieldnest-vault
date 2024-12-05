// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IBNBXStakeManagerV2} from "src/interface/external/stader/IBNBXStakeManagerV2.sol";

contract MockBNBxStakeManagerV2 is IBNBXStakeManagerV2 {
    function convertBnbToBnbX(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertBnbXToBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }
}
