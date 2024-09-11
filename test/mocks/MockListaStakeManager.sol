// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// mocks the lista stake manager to get the price in bnb
contract MockStakeManager {
    function convertSnBnbToBnb(uint256 _amountInSlisBnb) public pure returns (uint256) {
        return (_amountInSlisBnb * 1.02 ether) / 1 ether;
    }

    function convertBnbToSnBnb(uint256 _amount) public pure returns (uint256) {
        return (_amount * 1 ether) / 1.02 ether;
    }
}
