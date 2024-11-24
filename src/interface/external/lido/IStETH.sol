// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IStETH {
    function submit(address _referral) external payable returns (uint256);
}
