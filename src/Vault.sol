// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {Math} from "./Common.sol";

contract Vault is BaseVault {
    using Math for uint256;

    string public constant VAULT_VERSION = "0.1.1";

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    struct FeeStorage {
        /// @notice The base withdrawal fee in basis points (1e8 = 100%)
        uint64 baseWithdrawalFee;
    }
    /// @notice The fraction of the buffer below which flat fees apply, in basis points (1e8 = 100%). Only used by quadratic fees

    function _getFeeStorage() internal pure returns (FeeStorage storage $) {
        assembly {
            $.slot := 0xde924653ae91bd33356774e603163bd5862c93462f31acccae5f965be6e6599b
        }
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64 baseWithdrawalFee_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
        _initialize(admin, name, symbol, decimals_, baseWithdrawalFee_, countNativeAsset_, alwaysComputeTotalAssets_);
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64 baseWithdrawalFee_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;

        FeeStorage storage fees = _getFeeStorage();
        fees.baseWithdrawalFee = baseWithdrawalFee_;
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
