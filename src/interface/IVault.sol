// SPDX-License-Identifier: BSD-3-Clause 
pragma solidity ^0.8.24;

import {IERC4626} from "src/Common.sol";

interface IVault is IERC4626 {
    struct VaultStorage {
        bool paused;
        uint256 totalAssets;
        address provider;
        address buffer;
    }

    struct AssetParams {
        bool active;
        uint256 index;
        uint8 decimals;
    }

    struct AssetStorage {
        mapping(address => AssetParams) assets;
        address[] list;
    }

    struct StrategyParams {
        // index: used to list search the strategies
        uint256 index;
        // decimals: underlying decimals of the strategy token
        uint8 decimals;
        // shares: the number of strategy tokens held
        uint256 shares;
        // assets: current value of strategy tokens denominated in base
        uint256 assets;
        // debt: assets vault has sent to strategy denominated in base
        uint256 debt;
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

    event SetProvider(address indexed provider);
    event SetBuffer(address indexed buffer);
    event NewAsset(address indexed asset, uint256 decimals, uint256 index);
    event NewStrategy(address indexed strategy, uint256 index);
    event SetWhitelist(address target, bytes4 funcsig);
    event ProcessSuccess(address[] targets, uint256[] values, bytes[] data);
    event Pause(bool paused);
    event SetTotalAssets(uint256 totalAssets);

    // 4626-MAX
    function getAssets() external view returns (address[] memory list);
    function getAsset(address asset_) external view returns (AssetParams memory);
    function getStrategy(address strategy_) external view returns (StrategyParams memory);
    function getProcessorRule(address contractAddress, bytes4 funcSig) external returns (FunctionRule memory);
    function previewDepositAsset(address assetAddress, uint256 assets) external view returns (uint256);
    function depositAsset(address assetAddress, uint256 amount, address receiver) external returns (uint256);
    function provider() external view returns (address);
    function buffer() external view returns (address);

    // ADMIN
    function initialize(address admin_, string memory name_, string memory symbol_) external;
    function setProvider(address provider) external;
    function setBuffer(address buffer) external;
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule memory rule) external;

    function addStrategy(address strategy, uint8 decimals_) external;
    function addAsset(address asset_, uint8 decimals_) external;
    function pause(bool paused) external;

    function processStrategy(address strategy) external;
    function processAsset(address asset_) external;
    function processAccounting() external;
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}
