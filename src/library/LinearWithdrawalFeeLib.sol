// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultLib} from "src/library/VaultLib.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IVault} from "src/interface/IVault.sol";

library LinearWithdrawalFeeLib {
    function getFeeStorage() public pure returns (IVault.FeeStorage storage) {
        return VaultLib.getFeeStorage();
    }

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function feeOnRaw(uint256 amount, address user) public view returns (uint256) {
        return FeeMath.feeOnRaw(amount, feesToCharge(user));
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     * @dev Calculates the fee part of an amount `amount` that already includes fees.
     * Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     */
    function feeOnTotal(uint256 amount, address user) public view returns (uint256) {
        return FeeMath.feeOnTotal(amount, feesToCharge(user));
    }

    /**
     * @notice Returns the fee to charge for a user based on whether the fee is overridden for the user
     * @param user The address of the user.
     * @return The fee to charge.
     */
    function feesToCharge(address user) public view returns (uint64) {
        IVault.FeeStorage storage fees = getFeeStorage();
        bool isFeeOverridenForUser = fees.overriddenBaseWithdrawalFee[user].isOverridden;
        if (isFeeOverridenForUser) {
            return fees.overriddenBaseWithdrawalFee[user].baseWithdrawalFee;
        } else {
            return fees.baseWithdrawalFee;
        }
    }

    /**
     * @notice Function to set whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     */
    function overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_) public {
        IVault.FeeStorage storage fees = getFeeStorage();
        fees.overriddenBaseWithdrawalFee[user_] =
            IVault.OverriddenBaseWithdrawalFeeFields({baseWithdrawalFee: baseWithdrawalFee_, isOverridden: toOverride_});
        emit IVault.WithdrawalFeeOverridden(user_, baseWithdrawalFee_, toOverride_);
    }

    /**
     * @dev Implementation of setBaseWithdrawalFee
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     */
    function setBaseWithdrawalFee(uint64 baseWithdrawalFee_) public {
        if (baseWithdrawalFee_ > FeeMath.BASIS_POINT_SCALE) revert IVault.ExceedsMaxBasisPoints(baseWithdrawalFee_);
        IVault.FeeStorage storage fees = getFeeStorage();
        uint64 oldFee = fees.baseWithdrawalFee;
        fees.baseWithdrawalFee = baseWithdrawalFee_;
        emit IVault.SetBaseWithdrawalFee(oldFee, baseWithdrawalFee_);
    }

    /**
     * @notice Returns the base withdrawal fee
     * @return uint64 The base withdrawal fee in basis points (1/10000)
     */
    function getBaseWithdrawalFee() public view returns (uint64) {
        return getFeeStorage().baseWithdrawalFee;
    }

    /**
     * @notice Returns whether the withdrawal fee is overridden for a user
     * @param user_ The address of the user
     * @return The overridden fee fields for the user
     */
    function getOverriddenBaseWithdrawalFee(address user_)
        public
        view
        returns (IVault.OverriddenBaseWithdrawalFeeFields memory)
    {
        return getFeeStorage().overriddenBaseWithdrawalFee[user_];
    }
}
