// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

library Guard {
    function _getProcessorStorage() internal pure returns (IVault.ProcessorStorage storage $) {
        assembly {
            $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
        }
    }

    function setWhitelist(address target, bool allow) internal {
        IVault.ProcessorStorage storage $ = _getProcessorStorage();
        $.whitelist[target] = allow;
    }

    function isTargetAllowed(address target) internal view returns (bool) {
        IVault.ProcessorStorage storage $ = _getProcessorStorage();
        return $.whitelist[target];
    }

    function validateTarget(address target) internal view {
        if (!isTargetAllowed(target)) revert IVault.InvalidTarget(target);
    }
}
