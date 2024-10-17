// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVault {
    error ZeroAddress();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit();
    error InvalidAsset();
    error InvalidDecimals();
    error AssetNotFound();
    error Paused();

    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);
    event SetRateProvider(address indexed rateProvider);
    event AddAsset(address indexed asset, uint256 decimals, uint256 index);
    event ToggleAsset(address indexed asset, bool active);
    event Pause(bool paused);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    // Internal storage vs balanceOf storage
    // QUESTION: What issues are there with lending markets or other issues
    struct VaultStorage {
        // Balance of total assets priced in base asset
        uint256 totalAssets;
        // The price provider for asset conversions to the base asset
        address rateProvider;
        // If the vault is paused or not
        bool paused;
    }

    // QUESTION: Update the rate instead of the totalAssets?
    // QUESTION: How to avoid recalculating everything everytime
    struct AssetParams {
        // Activated or Deactivated
        bool active;
        // Index of this asset in the mapping
        uint256 index;
        // The decmials of the asset
        uint256 decimals;
        // Current vault deposit balance of this asset
        uint256 idleAssets;
        // deployedBalance
        // QUESTION: Is this required? We are counting this balance in
        // the strategy.assets
        uint256 deployedAssets;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        IERC20[] list;
    }

    struct StrategyParams {
        // Address of the Strategy
        address strategy;
        // Activated or Deactivated
        bool active;
        // The index of this strategy in the map
        uint256 index;
        // The percent in 100 * 100 Basis
        // QUESTION: Should this be on the Vault storage?
        uint256 ratio;
        // The Asset Address and allocated balance.
        mapping(address => uint256) assets;
    }

    struct StrategyStorage {
        mapping(address => StrategyParams) strategies;
        address[] list;
    }

    // 4626
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    // multi asset
    function assets() external view returns (address[] memory assets_);
    function convertToSharesAsset(address, uint256 assets) external view returns (uint256);
    function convertAssetToAssets(address, uint256 shares) external view returns (uint256);
    function maxDepositAsset(address, address) external view returns (uint256);
    function maxMintAsset(address, address) external view returns (uint256);
    function previewDepositAsset(uint256 assets) external view returns (uint256);
    function previewMintAsset(uint256 shares) external view returns (uint256);

    function depositAsset(address asset, uint256 assets, address receiver) external returns (uint256);
    function mintAsset(address asset, uint256 shares, address receiver) external returns (uint256);

    function getStrategies() external view returns (address[] memory);
    function getAssets() external view returns (address[] memory);
    function isStrategyActive(address strategy) external view returns (bool);

    // admin
    function initialize(address admin_, string memory name_, string memory symbol_) external;
    function addStrategy(address strategy) external;
    function removeStrategy(address strategy) external;
    function processAccounting() external returns (uint256);
    function setRateProvider(address rateProvider) external;
    function addAsset(address assetAddress, uint256 assetDecimals) external;
    function toggleAsset(address asset, bool active) external;

    struct ERC20Storage {
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
        uint256 totalSupply;
        string name;
        string symbol;
    }
}
