// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IValidator {
    /// @notice Validates a transaction before execution
    /// @param target The address the transaction will be sent to
    /// @param value The amount of ETH (in wei) that will be sent with the transaction
    /// @param data The calldata that will be sent with the transaction
    /// @dev This function should revert if the transaction is invalid
    /// @dev This function is called before executing a transaction
    function validate(address target, uint256 value, bytes calldata data) external view;
}
