// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "src/Common.sol";

interface IVault is IERC4626 {
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

    enum ParamType {
        UINT256,
        INT256,
        ADDRESS,
        BOOL,
        BYTES,
        STRING,
        BYTES32,
        CALLDATA
    }

    struct ParamRule {
        ParamType paramType; // Type of parameter
        bytes32 minValue; // Minimum value (if applicable)
        bytes32 maxValue; // Maximum value (if applicable)
        bool isArray; // Whether parameter is an array
        bool isRequired; // Whether parameter is required
        address[] allowList; // Allowed addresses (if applicable)
        address[] blockList; // Blocked addresses (if applicable)
    }

    struct FunctionRule {
        bool isActive; // Whether rule is active
        ParamRule[] paramRules; // Rules for each parameter
        uint256 maxGas; // Maximum gas allowed
        bool requireSuccess; // Whether call must succeed
    }

    struct ProcessorStorage {
        mapping(address => mapping(bytes4 => FunctionRule)) rules;
    }

    error Paused();
    error ZeroAddress();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit();
    error InvalidAsset(address);
    error InvalidStrategy(address);
    error InvalidTarget(address);
    error InvalidDecimals();
    error InvalidFunction(address target, bytes4 funcSig);
    error AssetNotFound();
    error DuplicateStrategy();
    error ExceededMaxWithdraw(address, uint256, uint256);
    error ExceededMaxRedeem(address, uint256, uint256);
    error ProcessFailed(bytes, bytes);
    error ProcessInvalid(bytes);
    error RateProviderNotSet();
    error BufferNotSet();

    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);
    event SetRateProvider(address indexed rateProvider);
    event SetBufferStrategy(address indexed bufferStrategy);
    event NewAsset(address indexed asset, uint256 decimals, uint256 index);
    event NewStrategy(address indexed strategy, uint256 index);
    event ToggleAsset(address indexed asset, bool active);
    event ToggleStrategy(address indexed strategy, bool active);
    event SetWhitelist(address target, bytes4 funcsig);
    event ProcessSuccess(address[] targets, uint256[] values, bytes[] data);
    event Pause(bool paused);

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
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule memory rule) external;

    function addStrategy(address strategy, uint8 decimals_) external;
    function addAsset(address asset_, uint8 decimals_) external;
    function toggleAsset(address asset_, bool active) external;
    function toggleStrategy(address strategy, bool active) external;
    function pause(bool paused) external;

    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data) external;
}
