// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {VaultLib} from "src/library/VaultLib.sol";
import {LinearWithdrawalFee} from "src/module/LinearWithdrawalFee.sol";

contract MockStrategy is BaseStrategy, LinearWithdrawalFee {
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external initializer {
        _initialize(admin, name, symbol, 18, false, true, alwaysComputeTotalAssets_, defaultAssetIndex_);
        // Optionally set default fee here or expose to constructor; skipping for simplicity
    }

    //// FEES ADMIN ////

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function _feeOnRaw(uint256 amount, address user) public view override returns (uint256) {
        return __feeOnRaw(amount, user);
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function _feeOnTotal(uint256 amount, address user) public view override returns (uint256) {
        return __feeOnTotal(amount, user);
    }

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
}
