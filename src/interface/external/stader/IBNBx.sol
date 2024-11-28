// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IBNBx {
    function delegate(string calldata _referralId)
        external
        payable
        returns (uint256);
}
