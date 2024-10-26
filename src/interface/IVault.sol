// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "src/Common.sol";

interface IVault is IERC4626 {
    error ZeroAddress();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit();
    error InvalidAsset();
    error InvalidStrategy();
    error InvalidDecimals();
    error InvalidRatio();
    error AssetNotFound();
    error Paused();
    error DuplicateStrategy();
    error ExceededMaxWithdraw(address, uint256, uint256);
    error ExceededMaxRedeem(address, uint256, uint256);
    error BadStrategy(address);
    error ProcessFailed(bytes);
    error RateProviderNotSet();
    error BufferNotSet();

    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);
    event SetRateProvider(address indexed rateProvider);
    event SetBufferStrategy(address indexed bufferStrategy);
    event NewAsset(address indexed asset, uint256 decimals, uint256 index);
    event NewStrategy(address indexed strategy, uint256 index);
    event ToggleAsset(address indexed asset, bool active);
    event Pause(bool paused);

    struct VaultStorage {
        bool paused;
        uint256 totalAssets;
        address rateProvider;
        address bufferStrategy;
    }

    struct AssetParams {
        bool active;
        uint256 index;
        uint8 decimals;
        uint256 idleBalance;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[] list;
    }

    struct StrategyParams {
        bool active;
        uint256 index;
        uint8 decimals;
        uint256 idleBalance;
    }

    struct StrategyStorage {
        mapping(address => StrategyParams) strategies;
        address[] list;
    }

    /// 4626
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    // 4626-MAX
    // function maxMintAsset(address assetAddress, address) external view returns (uint256);
    function getAssets() external view returns (address[] memory list);
    function getAsset(address asset_) external view returns (AssetParams memory);
    function getStrategy(address strategy_) external view returns (StrategyParams memory);
    function previewDepositAsset(address assetAddress, uint256 assets) external view returns (uint256);
    function depositAsset(address assetAddress, uint256 amount, address receiver) external returns (uint256);
    function rateProvider() external view returns (address);
    function bufferStrategy() external view returns (address);

    // ADMIN
    function initialize(address admin_, string memory name_, string memory symbol_) external;
    function setRateProvider(address rateProvider) external;
    function setBufferStrategy(address bufferStrategy) external;

    function addStrategy(address strategy, uint8 decimals_) external;
    function addAsset(address asset_, uint8 decimals_) external;
    function toggleAsset(address asset_, bool active) external;
    function pause(bool paused) external;

    function processAccounting() external;
}
