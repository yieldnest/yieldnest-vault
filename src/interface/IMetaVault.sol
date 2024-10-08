// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, IAccessControl} from "../Common.sol";

interface IMetaVault is IERC20, IAccessControl {

    error ZeroAddress();
    error InvalidString();
    error InvalidArray();

    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);

    struct VaultStorage {
        // Version
        uint8 version;
        // Deciamls of the Vault token
        uint8 decimals;
        // Base underlying asset of the Vault
        address denominationAsset;
        // Address of the Vault Module
        address metaModule;
        // Balance of total assets priced in denomination asset
        uint256 totalDebt;
    }

    struct AssetParams {
        // Address of the asset token
        address asset;
        // Activated or Deactivated
        bool active;
        // Index of this asset in the mapping
        uint8 index;
        // The decmials of the asset
        uint8 decimals;
        // Current vault balance of this asset
        uint256 currentBalance;
        // Outstanding Vault obligations in this asset
        uint256 currentDebt;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[256] assetList;
    }

    struct StrategyParams {
        // Address of the Strategy
        address strategy;
        // Activated or Deactivated
        bool active;
        // The index of this straegy in the map
        uint8 index;
        // Timestamp when the strategy was added.
        uint256 activation;
        // Timestamp of the strategies last accounting process.
        uint256 lastProcess;
        // The Asset Address and allocated balance.
        mapping(address => uint256) allocations;
    }

    struct StrategyStorage {
        mapping(address => StrategyParams) strategies;
        address[256] strategyList;
    }

    // read
    function assets() external view returns (address[] memory assets_);
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

    function getStrategies() external view returns (address[] memory);
    function isStrategyActive(address strategy) external view returns (bool);
    
    // write
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function depositAsset(address asset, uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    // admin
    function initialize(IERC20[] memory assets_, address admin_, string memory name_, string memory symbol_) external;
    function addStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
}