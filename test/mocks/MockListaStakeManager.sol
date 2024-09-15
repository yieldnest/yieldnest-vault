// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Math} from "src/Common.sol";

// mocks the lista stake manager to get the price in bnb
contract MockStakeManager {
    using Math for uint256;

    function convertSnBnbToBnb(uint256 _amount) public pure returns (uint256) {
        // Ensure the multiplication does not overflow
        require(_amount <= type(uint256).max / 1 ether, "Multiplication overflow");
        return (_amount * 1.02 ether) / 1 ether;
    }

    function convertBnbToSnBnb(uint256 _amount) public pure returns (uint256) {
        // Ensure the multiplication does not overflow
        require(_amount <= type(uint256).max / 1 ether, "Multiplication overflow");
        return (_amount * 1 ether) / 1.02 ether;
    }
}
