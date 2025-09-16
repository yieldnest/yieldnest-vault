// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

library MathUtils {

    function log10(uint256 x) internal pure returns (uint256) {
        require(x > 0, "log10 undefined for 0");

        uint256 result = 0;
        while (x >= 10) {
            x /= 10;
            result++;
        }
        return result;
    }
}