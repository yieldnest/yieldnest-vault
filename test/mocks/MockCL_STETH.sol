// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MockCL_STETH {
    uint256 private rate = 1e18;

    constructor() {}

    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, 1000000000000000000, 1630000000, 1630000000, 1);
    }
}
