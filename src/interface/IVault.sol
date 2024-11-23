// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "src/Common.sol";

interface IVault is IERC4626 {
    struct VaultStorage {
        bool paused;
        uint256 totalAssets;
        address provider;
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
        ADDRESS
    }

    struct ParamRule {
        ParamType paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
    }

    struct ProcessorStorage {
        uint256 lastProcessed;
        uint256 lastAccounting;
        mapping(address => mapping(bytes4 => FunctionRule)) rules;
    }

    error Paused();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroRate();
    error InvalidString();
    error InvalidArray();
    error ExceededMaxDeposit(address sender, uint256 amount, uint256 maxAssets);
    error InvalidAsset(address);
    error InvalidStrategy(address);
    error InvalidTarget(address);
    error InvalidDecimals();
    error InvalidFunction(address target, bytes4 funcSig);
    error AssetNotFound();
    error DuplicateAsset(address asset);
    error DuplicateStrategy(address strategy);
    error ExceededMaxWithdraw(address, uint256, uint256);
    error ExceededMaxRedeem(address, uint256, uint256);
    error ProcessFailed(bytes, bytes);
    error ProcessInvalid(bytes);
    error ProviderNotSet();
    error BufferNotSet();
    error DepositFailed();

    event DepositAsset(address indexed asset, address indexed vault, uint256 amount, address indexed receiver);
    event SetProvider(address indexed provider);
    event SetBufferStrategy(address indexed bufferStrategy);
    event NewAsset(address indexed asset, uint256 decimals, uint256 index);
    event NewStrategy(address indexed strategy, uint256 index);
    event ToggleAsset(address indexed asset, bool active);
    event ToggleStrategy(address indexed strategy, bool active);
    event SetWhitelist(address target, bytes4 funcsig);
    event ProcessSuccess(address[] targets, uint256[] values, bytes[] data);
    event Pause(bool paused);

    // 4626-MAX
    function getAssets() external view returns (address[] memory list);
    function getAsset(address asset_) external view returns (AssetParams memory);
    function getStrategy(address strategy_) external view returns (StrategyParams memory);
    function getProcessorRule(address contractAddress, bytes4 funcSig) external returns (FunctionRule memory);
    function previewDepositAsset(address assetAddress, uint256 assets) external view returns (uint256);
    function depositAsset(address assetAddress, uint256 amount, address receiver) external returns (uint256);
    function provider() external view returns (address);
    function bufferStrategy() external view returns (address);
    function processAccounting() external;

    // ADMIN
    function initialize(address admin_, string memory name_, string memory symbol_) external;
    function setProvider(address provider) external;
    function setBufferStrategy(address bufferStrategy) external;
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule memory rule) external;

    function addStrategy(address strategy, uint8 decimals_) external;
    function addAsset(address asset_, uint8 decimals_) external;
    function toggleAsset(address asset_, bool active) external;
    function toggleStrategy(address strategy, bool active) external;
    function pause(bool paused) external;

    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}
