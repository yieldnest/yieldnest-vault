// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IAssetRegistry {
    /* Events ***********************************************************************************************************/

    /// An asset was added to the registry
    event AssetAdded(address indexed asset, address indexed vault);

    /// An asset was removed from the registry
    event AssetRemoved(address indexed asset, address indexed vault);

    /* Errors ***********************************************************************************************************/

    /// Asset was already added to the registry
    error AssetAlreadyAdded();

    /// Asset was not added to the registry
    error AssetNotAdded();

    /// Vault was not empty
    error VaultNotEmpty();

    /// Vault was not found
    /// @param asset the asset address
    error VaultNotFound(address asset);

    /* External Functions ***********************************************************************************************/

    function addAsset(address vault) external;

    function getAssets() external view returns (address[] memory);

    function getVault(address asset) external view returns (address);

    function getVaultBalance(address asset) external view returns (uint256);

    function getVaultDepositLimit(address asset) external view returns (uint256);

    function hasAsset(address asset) external view returns (bool);

    function initialize(address configAddr) external;

    function removeAsset(address asset) external;
}
