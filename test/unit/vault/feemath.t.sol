// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {FeeMath} from "src/module/FeeMath.sol";

contract FeeMathTest is Test {
    uint256 public constant BASIS_POINT_SCALE = 1e8;
    uint256 public constant BUFFER_FEE_FLAT_PORTION = 8e7; // 80%

    function test_LinearFee(uint256 amount, uint256 fee) public pure {
        // Bound fee to valid range (0 to BASIS_POINT_SCALE)
        fee = bound(fee, 0, BASIS_POINT_SCALE);

        // Bound amount to avoid overflow when multiplying by fee
        amount = bound(amount, 0, 1000000 ether);

        uint256 expectedFee = (amount * fee) / BASIS_POINT_SCALE;
        uint256 actualFee = FeeMath.linearFee(amount, fee, FeeMath.FeeType.OnRaw);

        assertApproxEqAbs(actualFee, expectedFee, 1, "Linear fee calculation incorrect");
    }
}
