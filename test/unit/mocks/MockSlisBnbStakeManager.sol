// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";

contract MockSlisBnbStakeManager is ISlisBnbStakeManager {
    function convertSnBnbToBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertBnbToSnBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function deposit() external payable {}
}
