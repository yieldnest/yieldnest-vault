// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IVault} from "src/interface/IVault.sol";

abstract contract LinearWithdrawFee {
    //// FEES ////

    function _getFeeStorage() internal pure returns (IVault.FeeStorage storage) {
        return VaultLib.getFeeStorage();
    }

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function __feeOnRaw(uint256 amount, address user) public view returns (uint256) {
        return FeeMath.feeOnRaw(amount, _feesToCharge(user));
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     * @dev Calculates the fee part of an amount `amount` that already includes fees.
     * Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     */
    function __feeOnTotal(uint256 amount, address user) public view returns (uint256) {
        return FeeMath.feeOnTotal(amount, _feesToCharge(user));
    }

    /**
     * @notice Returns the fee to charge for a user based on whether the fee is overridden for the user
     * @param user The address of the user.
     * @return The fee to charge.
     */
    function _feesToCharge(address user) internal view returns (uint64) {
        IVault.FeeStorage storage fees = _getFeeStorage();
        bool isFeeOverridenForUser = fees.overriddenBaseWithdrawalFee[user].isOverridden;
        if (isFeeOverridenForUser) {
            return fees.overriddenBaseWithdrawalFee[user].baseWithdrawalFee;
        } else {
            return fees.baseWithdrawalFee;
        }
    }

    //// FEES ADMIN ////

    /**
     * @notice Internal function to set whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     */
    function _overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_) internal virtual {
        IVault.FeeStorage storage fees = _getFeeStorage();
        fees.overriddenBaseWithdrawalFee[user_] =
            IVault.OverriddenBaseWithdrawalFeeFields({baseWithdrawalFee: baseWithdrawalFee_, isOverridden: toOverride_});
        emit IVault.WithdrawalFeeOverridden(user_, baseWithdrawalFee_, toOverride_);
    }

    /**
     * @dev Internal implementation of setBaseWithdrawalFee
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     */
    function _setBaseWithdrawalFee(uint64 baseWithdrawalFee_) internal virtual {
        if (baseWithdrawalFee_ > FeeMath.BASIS_POINT_SCALE) revert IVault.ExceedsMaxBasisPoints(baseWithdrawalFee_);
        IVault.FeeStorage storage fees = _getFeeStorage();
        uint64 oldFee = fees.baseWithdrawalFee;
        fees.baseWithdrawalFee = baseWithdrawalFee_;
        emit IVault.SetBaseWithdrawalFee(oldFee, baseWithdrawalFee_);
    }

    /**
     * @notice Returns the base withdrawal fee
     * @return uint64 The base withdrawal fee in basis points (1/10000)
     */
    function baseWithdrawalFee() external view returns (uint64) {
        return _getFeeStorage().baseWithdrawalFee;
    }

    /**
     * @notice Returns whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @return bool Whether the withdrawal fee is exempted for the user
     */
    function overriddenBaseWithdrawalFee(address user_)
        external
        view
        returns (IVault.OverriddenBaseWithdrawalFeeFields memory)
    {
        return _getFeeStorage().overriddenBaseWithdrawalFee[user_];
    }
}
