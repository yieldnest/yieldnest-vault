// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract AssertUtils {
    function assertEqThreshold(
        uint256 actual,
        uint256 expected,
        uint256 threshold,
        string memory errorMessage
    ) internal pure {
        expected = expected <= threshold ? threshold : expected;
        require(actual > expected - threshold, string(abi.encodePacked(
            errorMessage,
            " however it's below threshold of",
            " Actual: ",
            Strings.toString(actual),
            " Expected: ",
            Strings.toString(expected),
            " Threshold: ",
            Strings.toString(threshold)
        )));
        require(actual < expected + threshold, string(abi.encodePacked(
            errorMessage,
            " however it's above threshold of",
            " Actual: ",
            Strings.toString(actual),
            " Expected: ",
            Strings.toString(expected),
            " Threshold: ",
            Strings.toString(threshold)
        )));
    }
}