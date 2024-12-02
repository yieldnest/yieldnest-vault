// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";

contract ynETHxVault is Vault {
    /**
     * @notice Initializes the vault.
     * @param decimals_ The number of decimals for the vault token.
     */
    function initializeV2(uint8 decimals_) external reinitializer(2) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.decimals = decimals_;
    }

    /**
     * @notice Initializer function that should not be called.
     * @dev This function overrides the base initializer to prevent it from being called.
     */
    function initialize(address, string memory, string memory, uint8) external virtual override {
        revert("Initialization not allowed");
    }
}
