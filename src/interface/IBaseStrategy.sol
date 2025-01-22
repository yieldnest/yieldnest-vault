// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IBaseStrategy {
    struct BaseStrategyStorage {
        bool hasAllocators;
        mapping(address => bool) isAssetWithdrawable;
    }

    struct SyncStrategyStorage {
        bool syncDeposit;
        bool syncWithdraw;
    }

    event WithdrawAsset(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        address asset,
        uint256 assets,
        uint256 shares
    );

    event SetHasAllocator(bool hasAllocator);
    event SetAssetWithdrawable(address asset, bool isWithdrawable);

    error AssetNotWithdrawable();

    /// ADMIN
    function getHasAllocator() external view returns (bool hasAllocators);
    function setHasAllocator(bool hasAllocators_) external;

    function getAssetWithdrawable(address asset) external view returns (bool isWithdrawable);
    function setAssetWithdrawable(address asset, bool isWithdrawable) external;

    function maxWithdrawAsset(address asset_, address owner) external view returns (uint256 maxAssets);
    function maxRedeemAsset(address asset_, address owner) external view returns (uint256 maxShares);
    function previewMintAsset(address asset_, uint256 shares) external view returns (uint256 assets);
    function previewRedeemAsset(address asset_, uint256 shares) external view returns (uint256 assets);
    function previewWithdrawAsset(address asset_, uint256 assets) external view returns (uint256 shares);
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);
    function redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);
    function addAsset(address asset_, uint8 decimals_, bool depositable_, bool withdrawable_) external;
    function addAsset(address asset_, bool depositable_, bool withdrawable_) external;
}
