// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";

library Guard {
    function validateCall(address target, uint256 value, bytes calldata data) internal view {
        bytes4 funcSig = bytes4(data[:4]);

        IVault.FunctionRule storage rule = _getProcessorStorage().rules[target][funcSig];

        if (!rule.isActive) revert RuleNotActive(target, funcSig);

        IValidator validator = rule.validator;
        if (address(validator) != address(0)) {
            validator.validate(target, value, data);
            return;
        }

        for (uint256 i = 0; i < rule.paramRules.length; i++) {
            if (rule.paramRules[i].paramType == IVault.ParamType.ADDRESS) {
                address addressValue = abi.decode(data[4 + i * 32:], (address));
                _validateAddress(addressValue, rule.paramRules[i]);
                continue;
            }
        }
    }

    function _validateAddress(address value, IVault.ParamRule storage rule) private view {
        if (rule.allowList.length > 0 && !_isInArray(value, rule.allowList)) revert AddressNotInAllowlist(value);
    }

    function _isInArray(address value, address[] storage array) private view returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return true;
            }
        }
        return false;
    }

    function _getProcessorStorage() internal pure returns (IVault.ProcessorStorage storage $) {
        assembly {
            $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
        }
    }

    error RuleNotActive(address, bytes4);
    error AddressNotInAllowlist(address);
}
