// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/Common.sol";

library Storage {
    
    bytes32 private constant VAULT_STORAGE_POSITION = keccak256("yieldnest.storage.vault");
    bytes32 private constant ASSET_STORAGE_POSITION = keccak256("yieldnest.storage.asset");
    bytes32 private constant STRAT_STORAGE_POSITION = keccak256("yieldnest.storage.strat");
    
    bytes32 private constant ERC20_STORAGE_POSITION = keccak256(
        abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)
    ) & ~bytes32(uint256(0xff)); 
    
    function _getVaultStorage() internal pure returns (IVault.VaultStorage storage $) {
        assembly {
            $.slot := VAULT_STORAGE_POSITION
        }
    }

    function _getAssetStorage() internal pure returns (IVault.AssetStorage storage $) {
        assembly {
            $.slot := ASSET_STORAGE_POSITION
        }
    }

    function _getStrategyStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            $.slot := STRAT_STORAGE_POSITION
        }
    }

    function _getERC20Storage() internal pure returns (IVault.ERC20Storage storage $) {
        assembly {
            $.slot := ERC20_STORAGE_POSITION
        }
    }
}