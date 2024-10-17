// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626, IAccessControl} from "../Common.sol";

interface IVault is IERC4626, IAccessControl {

    error ZeroAddress();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit();
    
    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);

    // Internal storage vs balanceOf storage
    // QUESTION: What issues are there with lending markets or other issues
    struct VaultStorage {
        // Version
        uint8 version;
        // Base underlying asset of the Vault
        address asset; // WETH
        // Decimals of the Vault token
        uint8 underlyingDecimals;
        // Balance of total assets priced in base asset
        uint256 totalAssets;
    }

    // QUESTION: Update the rate instead of the totalAssets?
    // QUESTION: How to avoid recalculating everything everytime
    struct AssetParams {
        // ERC20 asset token
        address asset;
        // Activated or Deactivated
        bool active;
        // Index of this asset in the mapping
        uint8 index;
        // The decmials of the asset
        uint8 decimals;
        // Current vault deposit balance of this asset
        uint256 idleAssets;
        // deployedBalance
        // QUESTION: Is this required? We are counting this balance in 
        // the strategy.assets
        uint256 deployedAssets;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[] list;
    }

    struct StrategyParams {
        // Address of the Strategy
        address strategy;
        // Activated or Deactivated
        bool active;
        // The index of this strategy in the map
        uint8 index;
        // The percent in 100 * 100 Basis
        // QUESTION: Should this be on the Vault storage?
        uint8 ratio;
        // The Asset Address and allocated balance.
        mapping(address => uint256) assets;
    }

    struct StrategyStorage {
        mapping(address => StrategyParams) strategies;
        address[] list;
    }

    // taken from oz ERC20Upgradeable
    struct ERC20Storage {
        mapping(address account => uint256) _balances;

        mapping(address account => mapping(address spender => uint256)) _allowances;

        uint256 _totalSupply;

        string _name;
        string _symbol;
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

    function previewDepositAsset(uint256 assets) external view returns (uint256);
    function previewMintAsset(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    function getStrategies() external view returns (address[] memory);
    function isStrategyActive(address strategy) external view returns (bool);
    
    // New function signatures for structs
    function getVaultStorage() external view returns (VaultStorage memory);
    function getAssetParams(address asset) external view returns (AssetParams memory);
    function getAssetStorage() external view returns (AssetStorage memory);
    function getStrategyParams(address strategy) external view returns (StrategyParams memory);
    function getStrategyStorage() external view returns (StrategyStorage memory);

    // write
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function depositAsset(address asset, uint256 assets, address receiver) external returns (uint256);

    function mint(uint256 shares, address receiver) external returns (uint256);
    function mintAsset(address asset, uint25 shares, address receiver) external returns (uint256);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    // admin
    function initialize(IERC20[] memory assets_, address admin_, string memory name_, string memory symbol_) external;
    function addStrategy(address strategy) external;
    function removeStrategy(address strategy) external;

    function processAccounting() external returns (uint256);
}
