// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IVault} from "src/interface/IVault.sol";
import {LinearWithdrawalFeeLib} from "src/library/LinearWithdrawalFeeLib.sol";

abstract contract LinearWithdrawalFee {
    //// FEES ////

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function __feeOnRaw(uint256 amount, address user) internal view returns (uint256) {
        return LinearWithdrawalFeeLib.feeOnRaw(amount, user);
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     * @dev Calculates the fee part of an amount `amount` that already includes fees.
     * Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     */
    function __feeOnTotal(uint256 amount, address user) internal view returns (uint256) {
        return LinearWithdrawalFeeLib.feeOnTotal(amount, user);
    }

    /**
     * @notice Returns the fee to charge for a user based on whether the fee is overridden for the user
     * @param user The address of the user.
     * @return The fee to charge.
     */
    function _feesToCharge(address user) internal view returns (uint64) {
        return LinearWithdrawalFeeLib.feesToCharge(user);
    }

    //// FEES ADMIN ///

    /**
     * @notice Internal function to set whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     */
    function _overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_) internal virtual {
        LinearWithdrawalFeeLib.overrideBaseWithdrawalFee(user_, baseWithdrawalFee_, toOverride_);
    }

    /**
     * @dev Internal implementation of setBaseWithdrawalFee
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     */
    function _setBaseWithdrawalFee(uint64 baseWithdrawalFee_) internal virtual {
        LinearWithdrawalFeeLib.setBaseWithdrawalFee(baseWithdrawalFee_);
    }

    /**
     * @notice Returns the base withdrawal fee
     * @return uint64 The base withdrawal fee in basis points (1/10000)
     */
    function baseWithdrawalFee() external view returns (uint64) {
        return LinearWithdrawalFeeLib.getBaseWithdrawalFee();
    }

    /**
     * @notice Returns whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @return The overridden fee fields for the user
     */
    function overriddenBaseWithdrawalFee(address user_)
        external
        view
        returns (IVault.OverriddenBaseWithdrawalFeeFields memory)
    {
        return LinearWithdrawalFeeLib.getOverriddenBaseWithdrawalFee(user_);
    }
}
