// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {VaultLib} from "src/library/VaultLib.sol";

contract VaultFees is BaseVault {
    string public constant VAULT_VERSION = "0.2.0";
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /// @notice The fraction of the buffer below which flat fees apply, in basis points (1e8 = 100%).
    /// Only used by quadratic fees

    function _getFeeStorage() internal pure returns (FeeStorage storage) {
        return VaultLib.getFeeStorage();
    }

    //// FEES ////

    function _feeOnRaw(uint256 assets) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        uint256 baseWithdrawalFee_ = fees.baseWithdrawalFee;
        if (baseWithdrawalFee_ == 0) {
            return 0;
        }
        return FeeMath.feeOnRaw(assets, baseWithdrawalFee_);
    }

    /// @dev Calculates the fee part of an amount `assets` that already includes fees.
    /// Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
    function _feeOnTotal(uint256 assets) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        uint256 baseWithdrawalFee_ = fees.baseWithdrawalFee;
        if (baseWithdrawalFee_ == 0) {
            return 0;
        }
        return FeeMath.feeOnTotal(assets, baseWithdrawalFee_);
    }

    //// FEES ADMIN ////

    /**
     * @notice Sets the base withdrawal fee for the vault
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setBaseWithdrawalFee(uint64 baseWithdrawalFee_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        if (baseWithdrawalFee_ > FeeMath.BASIS_POINT_SCALE) revert ExceedsMaxBasisPoints(baseWithdrawalFee_);
        FeeStorage storage fees = _getFeeStorage();
        uint64 oldFee = fees.baseWithdrawalFee;
        fees.baseWithdrawalFee = baseWithdrawalFee_;
        emit SetBaseWithdrawalFee(oldFee, baseWithdrawalFee_);
    }

    /**
     * @notice Returns the base withdrawal fee
     * @return uint64 The base withdrawal fee in basis points (1/10000)
     */
    function baseWithdrawalFee() external view returns (uint64) {
        return _getFeeStorage().baseWithdrawalFee;
    }
}
