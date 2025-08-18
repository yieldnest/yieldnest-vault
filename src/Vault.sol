// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {VaultLib} from "src/library/VaultLib.sol";

/**
 * @title Vault
 * @notice Multi-asset vault implementation extending ERC4626 standard
 * @dev Provides asset management with fee capabilities and flexible accounting
 *
 * Key features:
 * - Supports multiple deposit assets with common accounting denomination
 * - Configurable withdrawal fees managed by fee managers
 * - Buffer and strategy allocation for asset management
 * - Flexible accounting with real-time or cached asset valuation
 * - Role-based access control for administration and fee management
 */
contract Vault is BaseVault {
    string public constant VAULT_VERSION = "0.4.0";
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param baseWithdrawalFee_ The base withdrawal fee in basis points (1e8 = 100%).
     * @param countNativeAsset_ Whether the vault should count the native asset.
     * @param alwaysComputeTotalAssets_ Whether the vault should always compute total assets.
     * @param defaultAssetIndex_ The index of the default asset in the asset list.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64 baseWithdrawalFee_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external virtual initializer {
        _initialize(
            admin, // Address with admin privileges for the vault
            name, // Name of the vault token (ERC20)
            symbol, // Symbol of the vault token (ERC20)
            decimals_, // Decimal precision for the vault token
            true, // Start the vault in paused state for safety
            countNativeAsset_, // Whether to include native ETH in asset calculations
            alwaysComputeTotalAssets_, // Whether to compute assets in real-time vs using cached values
            defaultAssetIndex_ // Index of the default asset in the asset list
        );

        _setBaseWithdrawalFee(baseWithdrawalFee_);
    }

    //// FEES ////

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function _feeOnRaw(uint256 amount, address user) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        bool isFeeOverridenForUser = fees.overriddenBaseWithdrawalFee[user].isOverridden;
        uint64 feesToCharge;
        if (isFeeOverridenForUser) {
            feesToCharge = fees.overriddenBaseWithdrawalFee[user].baseWithdrawalFee;
        } else {
            feesToCharge = fees.baseWithdrawalFee;
        }
        return FeeMath.feeOnRaw(amount, feesToCharge);
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     * @dev Calculates the fee part of an amount `amount` that already includes fees.
     * Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     */
    function _feeOnTotal(uint256 amount, address user) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        bool isFeeOverridenForUser = fees.overriddenBaseWithdrawalFee[user].isOverridden;
        uint64 feesToCharge;
        if (isFeeOverridenForUser) {
            feesToCharge = fees.overriddenBaseWithdrawalFee[user].baseWithdrawalFee;
        } else {
            feesToCharge = fees.baseWithdrawalFee;
        }
        return FeeMath.feeOnTotal(amount, feesToCharge);
    }

    //// FEES ADMIN ////

    /**
     * @notice Sets the base withdrawal fee for the vault
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setBaseWithdrawalFee(uint64 baseWithdrawalFee_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        _setBaseWithdrawalFee(baseWithdrawalFee_);
    }

    /**
     * @notice Sets whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_)
        external
        virtual
        onlyRole(FEE_MANAGER_ROLE)
    {
        _overrideBaseWithdrawalFee(user_, baseWithdrawalFee_, toOverride_);
    }

    /**
     * @notice Internal function to set whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     */
    function _overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_) internal virtual {
        FeeStorage storage fees = _getFeeStorage();
        fees.overriddenBaseWithdrawalFee[user_] =
            OverriddenBaseWithdrawalFeeFields({baseWithdrawalFee: baseWithdrawalFee_, isOverridden: toOverride_});
        emit WithdrawalFeeOverridden(user_, baseWithdrawalFee_, toOverride_);
    }

    /**
     * @dev Internal implementation of setBaseWithdrawalFee
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     */
    function _setBaseWithdrawalFee(uint64 baseWithdrawalFee_) internal virtual {
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

    /**
     * @notice Returns whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @return bool Whether the withdrawal fee is exempted for the user
     */
    function overriddenBaseWithdrawalFee(address user_)
        external
        view
        returns (OverriddenBaseWithdrawalFeeFields memory)
    {
        return _getFeeStorage().overriddenBaseWithdrawalFee[user_];
    }
}
