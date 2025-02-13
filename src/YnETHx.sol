// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";

contract YnETHx is Vault {
    /**
     * @dev Storage structure for ERC4626 asset information.
     * @param _asset The ERC20 token associated with the strategy.
     * @param _underlyingDecimals The number of decimals of the underlying asset.
     */
    struct ERC4626Storage {
        IERC20 _asset;
        uint8 _underlyingDecimals;
    }

    /**
     * @notice Retrieves the storage location for ERC4626 storage.
     * @dev The storage slot is hardcoded for optimized access.
     * @return $ The ERC4626Storage reference at the designated slot.
     */
    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    /**
     * @notice Initializes the vault.
     * @param decimals_ The number of decimals for the vault token.
     */
    function initializeV2(uint8 decimals_, uint64 baseWithdrawalFee_) external reinitializer(2) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = true;

        FeeStorage storage fees = _getFeeStorage();
        fees.baseWithdrawalFee = baseWithdrawalFee_;

        ERC4626Storage storage erc4626Storage = _getERC4626Storage();

        // Clear existing storage
        erc4626Storage._asset = IERC20(0x0000000000000000000000000000000000000000);
        erc4626Storage._underlyingDecimals = 0;
    }
}
