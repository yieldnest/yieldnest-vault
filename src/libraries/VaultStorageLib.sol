// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

library VaultStorageLib {
    // Storage structs remain the same
    struct VaultStorage {
        bool paused;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint8 decimals;
        uint256 totalAssets;
        address provider;
        address buffer;
    }

    struct AssetStorage {
        mapping(address => IVault.AssetParams) assets;
        address[] list;
    }

    struct ProcessorStorage {
        mapping(address => mapping(bytes4 => IVault.FunctionRule)) rules;
    }

    struct FeeStorage {
        /// @notice The base withdrawal fee in basis points (1e8 = 100%)
        uint64 baseWithdrawalFee;
    }

    /**
     * @notice Internal function to get the vault storage.
     * @return $ The vault storage.
     */
    function getVaultStorage() public pure returns (VaultStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.vault")
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }

    /**
     * @notice Internal function to get the asset storage.
     * @return $ The asset storage.
     */
    function getAssetStorage() public pure returns (AssetStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.asset")
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }
    /**
     * @notice Internal function to get the processor storage.
     * @return $ The processor storage.
     */

    function getProcessorStorage() public pure returns (ProcessorStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.vault")
            $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
        }
    }

    function getFeeStorage() public pure returns (FeeStorage storage $) {
        assembly {
            $.slot := 0xde924653ae91bd33356774e603163bd5862c93462f31acccae5f965be6e6599b
        }
    }
}
