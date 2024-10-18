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

    struct VaultStorage {
        uint256 totalAssets;
        address rateProvider;
        bool paused;
    }

    struct AssetParams {
        bool active;
        uint256 index;
        uint8 decimals;
        uint256 idleAssets;
        uint256 deployedAssets;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[] list;
    }

    struct StrategyParams {
        bool active;
        uint256 index;
        uint256 ratio;
        mapping(address => uint256) assets;
    }

    struct StrategyStorage {
        mapping(address => StrategyParams) strategies;
        address[] list;
    }

    function initialize(address admin_, string memory name_, string memory symbol_) external;
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewDeposit(uint256 assetAmount) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assetAmount) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function deposit(uint256 assetAmount, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 assetAmount, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function assets() external view returns (address[] memory assets_);
    
    // function maxMintAsset(address assetAddress, address) external view returns (uint256);
    function previewDepositAsset(address assetAddress, uint256 assetAmount) external view returns (uint256);
    function previewMintAsset(address assetAddress, uint256 shares) external view returns (uint256);
    function depositAsset(address assetAddress, uint256 amount, address receiver) external returns (uint256);
    // function getStrategies() external view returns (address[] memory);
    // function isStrategyActive(address strategy) external view returns (bool);
    // function addStrategy(address strategy) external;
    // function processAccounting() external returns (uint256);
    function setRateProvider(address rateProvider) external;
    function addAsset(address assetAddress, uint8 assetDecimals) external;
    function toggleAsset(address assetAddress, bool active) external;
    function pause(bool paused) external;
}
