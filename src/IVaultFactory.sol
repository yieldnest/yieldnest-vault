// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, IERC4626, IAccessControl} from "src/Common.sol";

interface IVaultFactory is IAccessControl {
    enum VaultType {
        SingleAsset,
        MultiAsset
    }

    /**
     * @dev Represents a vault with its timelock, name, symbol, and type.
     * @param timelock The address of the timelock controller for the vault.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param vaultType The type of the vault, either SingleAsset or MultiAsset.
     */
    struct Vault {
        address timelock;
        string name;
        string symbol;
        VaultType vaultType;
    }

    function timelock() external view returns (address);

    function singleVaultImpl() external view returns (address);

    function multiVaultImpl() external view returns (address);

    function initialize(address singleVaultImpl_, address admin, address timelock_) external;

    function createSingleVault(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint256 minDelay_,
        address[] memory proposers_,
        address[] memory executors_
    ) external returns (address);

    function setVaultVersion(address implementation_, VaultType vaultType) external;
}
