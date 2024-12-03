// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";

contract ynETHxVault is BaseVault {
    /**
     * @notice Initializes the vault.
     * @param decimals_ The number of decimals for the vault token.
     */
    function initialize(uint8 decimals_) external reinitializer(2) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.decimals = decimals_;
    }
}
