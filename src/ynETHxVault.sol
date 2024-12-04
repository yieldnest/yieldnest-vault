// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";

contract ynETHxVault is Vault {
    /**
     * @notice Initializes the vault.
     * @param decimals_ The number of decimals for the vault token.
     */
    function initializeV2(uint8 decimals_, uint64 baseWithdrawalFee_) external reinitializer(2) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = true;

        FeeStorage storage fees = _getFeeStorage();
        fees.baseWithdrawalFee = baseWithdrawalFee_;
    }
}
