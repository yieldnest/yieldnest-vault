// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {Math} from "./Common.sol";

contract Vault is BaseVault {
    using Math for uint256;

    struct FeeStorage {
        uint64 baseWithdrawalFee;
        uint64 bufferFlatFeeFraction;
        uint64 vaultBufferFraction;
    }

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
    function initialize(address admin, string memory name, string memory symbol, uint8 decimals_)
        external
        virtual
        initializer
    {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
    }

    //// FEES ////

    function _feeOnRaw(uint256 assets) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        uint256 baseWithdrawalFee = fees.baseWithdrawalFee;
        uint256 bufferFlatFeeFraction = fees.bufferFlatFeeFraction;
        uint256 vaultBufferFraction = fees.vaultBufferFraction;
        if (baseWithdrawalFee == 0) {
            return 0;
        }

        uint256 bufferAvailableAmount = IStrategy(buffer()).totalAssets();
        uint256 totalAssets_ = totalAssets();
        uint256 bufferMaxSize = _bufferMaxSize(totalAssets_, vaultBufferFraction);

        uint256 feeInAssets = FeeMath.quadraticBufferFee(
            assets,
            bufferMaxSize,
            bufferAvailableAmount,
            bufferFlatFeeFraction,
            baseWithdrawalFee,
            FeeMath.FeeType.OnRaw
        );

        return feeInAssets;
    }

    /// @dev Calculates the fee part of an amount `assets` that already includes fees.
    /// Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
    function _feeOnTotal(uint256 assets) public view override returns (uint256) {
        FeeStorage storage fees = _getFeeStorage();
        uint256 withdrawalFee = fees.baseWithdrawalFee;
        if (withdrawalFee == 0) {
            return 0;
        }

        return assets.mulDiv(withdrawalFee, withdrawalFee + FeeMath.BASIS_POINT_SCALE, Math.Rounding.Ceil);
    }

    function _bufferMaxSize(uint256 totalAssets_, uint256 bufferFraction_) internal pure returns (uint256) {
        return totalAssets_.mulDiv(bufferFraction_, FeeMath.BASIS_POINT_SCALE, Math.Rounding.Floor);
    }

    //// FEES ADMIN ////

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /** @notice Sets the base withdrawal fee for the vault
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setBaseWithdrawalFee(uint64 baseWithdrawalFee_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        _getFeeStorage().baseWithdrawalFee = baseWithdrawalFee_;
    }

    /** @notice Sets the flat fee fraction applied when using the buffer
     * @param bufferFlatFeeFraction_ The new buffer flat fee fraction in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setBufferFlatFeeFraction(uint64 bufferFlatFeeFraction_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        _getFeeStorage().bufferFlatFeeFraction = bufferFlatFeeFraction_;
    }

    /** @notice Sets the maximum buffer size as a fraction of total assets
     * @param vaultBufferFraction_ The new vault buffer fraction in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setVaultBufferFraction(uint64 vaultBufferFraction_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        _getFeeStorage().vaultBufferFraction = vaultBufferFraction_;
    }
}
