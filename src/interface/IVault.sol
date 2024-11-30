// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "src/Common.sol";

interface IVault is IERC4626 {
    struct VaultStorage {
        uint256 totalAssets;
        address provider;
        address buffer;
        bool paused;
        uint8 decimals;
    }

    struct AssetParams {
        uint256 index;
        bool active;
        uint8 decimals;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[] list;
    }

    struct ProcessorStorage {
        uint256 lastProcessed;
        uint256 lastAccounting;
        mapping(address => bool) whitelist;
    }

    error Paused();
    error Unpaused();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroRate();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit(address sender, uint256 amount, uint256 maxAssets);
    error InvalidAsset(address);
    error InvalidTarget(address);
    error InvalidDecimals();
    error DuplicateAsset(address asset);
    error ExceededMaxWithdraw(address, uint256, uint256);
    error ExceededMaxRedeem(address, uint256, uint256);
    error ProcessFailed(bytes, bytes);
    error ProcessInvalid(bytes);
    error ProviderNotSet();
    error BufferNotSet();
    error DepositFailed();
    error AssetNotActive();

    event SetProvider(address indexed provider);
    event SetBuffer(address indexed buffer);
    event NewAsset(address indexed asset, uint256 decimals, uint256 index);
    event ProcessSuccess(address[] targets, uint256[] values, bytes[] data);
    event Pause(bool paused);
    event AddTarget(address indexed target);
    event RemoveTarget(address indexed target);
    event NativeDeposit(uint256 amount);
    event ProcessAccounting(uint256 timestamp, uint256 totalAssets);

    // 4626-MAX
    function getAssets() external view returns (address[] memory list);
    function getAsset(address asset_) external view returns (AssetParams memory);
    function isTargetWhitelisted(address contractAddress) external returns (bool);
    function previewDepositAsset(address assetAddress, uint256 assets) external view returns (uint256);
    function depositAsset(address assetAddress, uint256 amount, address receiver) external returns (uint256);
    function provider() external view returns (address);
    function buffer() external view returns (address);

    // ADMIN
    function setProvider(address provider) external;
    function setBuffer(address buffer) external;
    function addTarget(address target, bytes memory data) external;
    function removeTarget(address target) external;

    function addAsset(address asset_, uint8 decimals_, bool active_) external;
    function pause() external;
    function unpause() external;

    function processAccounting() external;
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}
