// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20Upgradeable,
    IERC20,
    IERC20Metadata,
    Math,
    ReentrancyGuardUpgradeable,
    SafeERC20
} from "src/Common.sol";

import {VaultLib} from "src/library/VaultLib.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";

/**
 * @title BaseVault
 * @notice Base contract for vault implementations that support multiple assets
 * @dev This contract implements the ERC4626 standard with extensions to support multiple assets
 *
 * The BaseVault has two key asset concepts:
 *
 * 1. Base Asset: The common denomination used internally for accounting.
 *    - All assets are converted to this base unit for consistent accounting
 *    - The base asset has a fixed decimal precision (typically 18 decimals)
 *    - totalBaseAssets() tracks the vault's total value in this base denomination
 *
 * 2. Default Asset: The underlying asset used for standard ERC4626 operations.
 *    - Specified by the defaultAssetIndex in VaultStorage
 *    - Returned by the asset() function
 *    - Used for deposit(), withdraw(), mint(), and redeem() when no asset is specified
 *       - Can be the same as base asset (defaultAssetIndex == 0)
 *    - Can be different from the base asset (defaultAssetIndex == 1)
 *
 *  REQUIREMENT: default Asset MUST be the underyling asset of Base Asset.
 *               Example: Default Asset is USDC, Base Asset is Wrapped USDC.
 *
 * The vault maintains a list of supported assets, each with their own decimal precision.
 * When assets enter or leave the vault, they are converted to/from the base asset denomination
 * for consistent accounting across different asset types.
 * The vault also includes a processAccounting function that updates the vault's total assets.
 * This function:
 * - Computes the current total assets by querying the buffer and other strategies
 * - Updates the vault's totalAssets storage value
 *
 * This accounting mechanism ensures the vault's reported asset values remain accurate over time,
 * gas efficiency with accuracy by:
 * - Using cached totalAssets values by default to save gas on frequent read operations
 * - Providing an explicit processAccounting() function that updates the cached value when needed
 * - Offering an alwaysComputeTotalAssets toggle for cases where real-time accuracy is preferred
 *   despite the higher gas cost of querying external contracts on each totalAssets() call
 */
abstract contract BaseVault is IVault, ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    /// INITIALIZATION

    /**
     * @notice Internal function to initialize the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param paused_ Whether the vault should start in a paused state.
     * @param countNativeAsset_ Whether the vault should count the native asset.
     * @param alwaysComputeTotalAssets_ Whether the vault should always compute total assets.
     * @param defaultAssetIndex_ The index of the default asset in the asset list.
     */
    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool paused_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = paused_;
        if (decimals_ == 0) {
            revert InvalidDecimals();
        }
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;

        // The defaultAssetIndex must be 0 or 1 because:
        // 1. When an asset is deleted, it's replaced with the last asset in the array
        // 2. The base asset (index 0) and default asset should never be deleted
        // 3. Therefore, they must be the first two positions in the array
        // 4. Or if defaultAssetIndex is 0, then the base asset is also the default asset
        if (defaultAssetIndex_ > 1) {
            revert InvalidDefaultAssetIndex(defaultAssetIndex_);
        }
        vaultStorage.defaultAssetIndex = defaultAssetIndex_;
    }

    /**
     * @notice Returns the address of the Default Asset.
     * @return address The address of the asset.
     * @dev The ERC4626-interface underlying asset is the default asset at defaultAssetIndex
     */
    function asset() public view virtual returns (address) {
        return _getAssetStorage().list[_getVaultStorage().defaultAssetIndex];
    }

    /**
     * @notice Returns the number of decimals of the vault.
     * @return uint256 The number of decimals.
     */
    function decimals() public view virtual override(ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return _getVaultStorage().decimals;
    }

    /**
     * @notice Returns the total assets held by the vault denominated in the default asset.
     * @dev The ERC4626 interface underyling asset is the default asset.
     * @return uint256 The total assets.
     */
    function totalAssets() public view virtual returns (uint256) {
        return VaultLib.convertBaseToAsset(asset(), totalBaseAssets());
    }

    /**
     * @notice Returns the total assets held by the vault denominated in the Base Asset.
     * @dev Either returns the cached total assets or computes them in real-time
     *      based on the alwaysComputeTotalAssets setting.
     * @return uint256 The total base assets.
     */
    function totalBaseAssets() public view virtual returns (uint256) {
        if (_getVaultStorage().alwaysComputeTotalAssets) {
            return computeTotalAssets();
        }
        return _getVaultStorage().totalAssets;
    }

    /**
     * @notice Returns if the vault is counting native assets.
     * @return bool True if the vault is counting native assets.
     */
    function countNativeAsset() public view virtual returns (bool) {
        return _getVaultStorage().countNativeAsset;
    }

    /**
     * @notice Returns the index of the default asset.
     * @return uint256 The index of the default asset.
     */
    function defaultAssetIndex() public view virtual returns (uint256) {
        return _getVaultStorage().defaultAssetIndex;
    }

    /**
     * @notice Converts a given amount of assets to shares.
     * @param assets The amount of assets to convert.
     * @return shares The equivalent amount of shares.
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        (shares,) = _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice Converts a given amount of shares to assets.
     * @param shares The amount of shares to convert.
     * @return assets The equivalent amount of assets.
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256 shares) {
        (shares,) = _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of assets that would be required to mint a given amount of shares.
     * @param shares The amount of shares to mint.
     * @return assets The equivalent amount of assets.
     */
    function previewMint(uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset(), shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of shares that would be required to withdraw a given amount of assets.
     * @param assets The amount of assets to withdraw.
     * @return shares The equivalent amount of shares.
     */
    function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
        uint256 fee = _feeOnRaw(assets);
        (shares,) = _convertToShares(asset(), assets + fee, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeem(uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset(), shares, Math.Rounding.Floor);
        return assets - _feeOnTotal(assets);
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited by a given owner.
     * @return uint256 The maximum amount of assets.
     */
    function maxDeposit(address) public view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }
        return type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted.
     * @return uint256 The maximum amount of shares.
     */
    function maxMint(address) public view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }
        return type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return uint256 The maximum amount of assets.
     */
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }

        uint256 bufferAssets = IStrategy(buffer()).maxWithdraw(address(this));
        if (bufferAssets == 0) {
            return 0;
        }

        uint256 ownerShares = balanceOf(owner);
        uint256 maxAssets = previewRedeem(ownerShares);

        return bufferAssets < maxAssets ? bufferAssets : maxAssets;
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return uint256 The maximum amount of shares.
     */
    function maxRedeem(address owner) public view virtual returns (uint256) {
        if (paused()) {
            return 0;
        }

        uint256 bufferAssets = IStrategy(buffer()).maxWithdraw(address(this));
        if (bufferAssets == 0) {
            return 0;
        }

        uint256 ownerShares = balanceOf(owner);
        return bufferAssets < previewRedeem(ownerShares) ? previewWithdraw(bufferAssets) : ownerShares;
    }

    /**
     * @notice Deposits a given amount of assets and assigns the equivalent amount of shares to the receiver.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function deposit(uint256 assets, address receiver) public virtual nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        (uint256 shares, uint256 baseAssets) = _convertToShares(asset(), assets, Math.Rounding.Floor);
        _deposit(asset(), _msgSender(), receiver, assets, shares, baseAssets);
        return shares;
    }

    /**
     * @notice Mints a given amount of shares and assigns the equivalent amount of assets to the receiver.
     * @param shares The amount of shares to mint.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of assets.
     */
    function mint(uint256 shares, address receiver) public virtual nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        (uint256 assets, uint256 baseAssets) = _convertToAssets(asset(), shares, Math.Rounding.Floor);
        _deposit(asset(), _msgSender(), receiver, assets, shares, baseAssets);
        return assets;
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = previewWithdraw(assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Redeems a given amount of shares and transfers the equivalent amount of assets to the receiver.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 assets)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    //// 4626-MAX ////

    /**
     * @notice Returns the list of asset addresses.
     * @return addresses The list of asset addresses.
     */
    function getAssets() public view virtual returns (address[] memory) {
        return _getAssetStorage().list;
    }

    /**
     * @notice Returns the parameters of a given asset.
     * @param asset_ The address of the asset.
     * @return AssetParams The parameters of the asset.
     */
    function getAsset(address asset_) public view virtual returns (AssetParams memory) {
        return _getAssetStorage().assets[asset_];
    }

    /**
     * @notice Returns the function rule for a given contract address and function signature.
     * @param contractAddress The address of the contract.
     * @param funcSig The function signature.
     * @return FunctionRule The function rule.
     */
    function getProcessorRule(address contractAddress, bytes4 funcSig)
        public
        view
        virtual
        returns (FunctionRule memory)
    {
        return _getProcessorStorage().rules[contractAddress][funcSig];
    }

    /**
     * @notice Returns whether the vault is paused.
     * @return bool True if the vault is paused, false otherwise.
     */
    function paused() public view returns (bool) {
        return _getVaultStorage().paused;
    }

    /**
     * @notice Returns the address of the provider.
     * @return address The address of the provider.
     */
    function provider() public view returns (address) {
        return _getVaultStorage().provider;
    }

    /**
     * @notice Returns the address of the buffer strategy.
     * @return address The address of the buffer strategy.
     */
    function buffer() public view virtual returns (address) {
        return _getVaultStorage().buffer;
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets for a specific asset.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewDepositAsset(address asset_, uint256 assets) public view virtual returns (uint256 shares) {
        (shares,) = _convertToShares(asset_, assets, Math.Rounding.Floor);
    }

    /**
     * @notice Deposits a given amount of assets for a specific asset and assigns shares to the receiver.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function depositAsset(address asset_, uint256 assets, address receiver)
        public
        virtual
        nonReentrant
        returns (uint256)
    {
        if (paused()) {
            revert Paused();
        }
        (uint256 shares, uint256 baseAssets) = _convertToShares(asset_, assets, Math.Rounding.Floor);
        _deposit(asset_, _msgSender(), receiver, assets, shares, baseAssets);
        return shares;
    }

    //// INTERNAL ////

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset convertion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal virtual {
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        _addTotalAssets(baseAssets);

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
        _mint(receiver, shares);

        // 4626 event
        emit Deposit(caller, receiver, assets, shares);

        // 4626-MAX event
        emit DepositAsset(caller, receiver, asset_, assets, baseAssets, shares);
    }

    /**
     * @notice Internal function to add to total assets.
     * @param baseAssets The amount of base assets to add.
     */
    function _addTotalAssets(uint256 baseAssets) internal virtual {
        VaultLib.addTotalAssets(baseAssets);
    }

    /**
     * @notice Internal function to subtract from total assets.
     * @param baseAssets The amount of base assets to subtract.
     */
    function _subTotalAssets(uint256 baseAssets) internal virtual {
        VaultLib.subTotalAssets(baseAssets);
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
    {
        VaultStorage storage vaultStorage = _getVaultStorage();
        _subTotalAssets(VaultLib.convertAssetToBase(asset(), assets));
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        IStrategy(vaultStorage.buffer).withdraw(assets, receiver, address(this));

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to convert vault shares to the base asset.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to convert.
     * @param rounding The rounding direction.
     * @return (uint256 assets, uint256 baseAssets) The equivalent amount of assets.
     */
    function _convertToAssets(address asset_, uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256, uint256)
    {
        return VaultLib.convertToAssets(asset_, shares, rounding);
    }

    /**
     * @notice Internal function to convert assets to shares.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction.
     * @return (uint256 shares, uint256 baseAssets) The equivalent amount of shares.
     */
    function _convertToShares(address asset_, uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256, uint256)
    {
        return VaultLib.convertToShares(asset_, assets, rounding);
    }

    /**
     * @notice Internal function to convert an asset amount to base denomination.
     * @param asset_ The address of the asset.
     * @param assets The amount of the asset.
     * @return uint256 The equivalent amount in base denomination.
     */
    function _convertAssetToBase(address asset_, uint256 assets) internal view virtual returns (uint256) {
        return VaultLib.convertAssetToBase(asset_, assets);
    }

    /**
     * @notice Internal function to convert base denominated amount to asset value.
     * @param asset_ The address of the asset.
     * @param assets The amount of the asset.
     * @return uint256 The equivalent amount of assets.
     */
    function _convertBaseToAsset(address asset_, uint256 assets) internal view virtual returns (uint256) {
        return VaultLib.convertBaseToAsset(asset_, assets);
    }

    /**
     * @notice Internal function to get the vault storage.
     * @return The vault storage.
     */
    function _getVaultStorage() internal pure virtual returns (VaultStorage storage) {
        return VaultLib.getVaultStorage();
    }

    /**
     * @notice Internal function to get the asset storage.
     * @return The asset storage.
     */
    function _getAssetStorage() internal pure returns (AssetStorage storage) {
        return VaultLib.getAssetStorage();
    }

    /**
     * @notice Internal function to get the processor storage.
     * @return The processor storage.
     */
    function _getProcessorStorage() internal pure returns (ProcessorStorage storage) {
        return VaultLib.getProcessorStorage();
    }

    //// ADMIN ////

    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");

    /**
     * @notice Sets the provider.
     * @param provider_ The address of the provider.
     */
    function setProvider(address provider_) external virtual onlyRole(PROVIDER_MANAGER_ROLE) {
        VaultLib.setProvider(provider_);
    }

    /**
     * @notice Sets the buffer strategy.
     * @param buffer_ The address of the buffer strategy.
     */
    function setBuffer(address buffer_) external virtual onlyRole(BUFFER_MANAGER_ROLE) {
        VaultLib.setBuffer(buffer_);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule calldata rule)
        public
        virtual
        onlyRole(PROCESSOR_MANAGER_ROLE)
    {
        _setProcessorRule(target, functionSig, rule);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function _setProcessorRule(address target, bytes4 functionSig, FunctionRule calldata rule) internal virtual {
        _getProcessorStorage().rules[target][functionSig] = rule;
        emit SetProcessorRule(target, functionSig, rule);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function setProcessorRules(address[] calldata target, bytes4[] calldata functionSig, FunctionRule[] calldata rule)
        public
        virtual
        onlyRole(PROCESSOR_MANAGER_ROLE)
    {
        uint256 targetLength = target.length;
        if (targetLength != functionSig.length || targetLength != rule.length) {
            revert InvalidArray();
        }

        for (uint256 i = 0; i < targetLength; i++) {
            _setProcessorRule(target[i], functionSig[i], rule[i]);
        }
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param active_ Whether the asset is active or not.
     */
    function addAsset(address asset_, bool active_) public virtual onlyRole(ASSET_MANAGER_ROLE) {
        _addAsset(asset_, IERC20Metadata(asset_).decimals(), active_);
    }

    function _addAsset(address asset_, uint8 decimals_, bool active_) internal virtual {
        VaultLib.addAsset(asset_, decimals_, active_);
    }

    /**
     * @notice Updates an existing asset's parameters in the vault.
     * @param index The index of the asset to update.
     * @param fields The AssetUpdateFields struct containing the updated fields.
     */
    function updateAsset(uint256 index, AssetUpdateFields calldata fields)
        public
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _updateAsset(index, fields);
    }

    function _updateAsset(uint256 index, AssetUpdateFields calldata fields) internal virtual {
        VaultLib.updateAsset(index, fields);
    }

    /**
     * @notice Deletes an existing asset from the vault.
     * @param index The index of the asset to delete.
     */
    function deleteAsset(uint256 index) public virtual onlyRole(ASSET_MANAGER_ROLE) {
        _deleteAsset(index);
    }

    function _deleteAsset(uint256 index) internal virtual {
        VaultLib.deleteAsset(index);
    }

    /**
     * @notice Sets whether the vault should always compute total assets.
     * @param alwaysComputeTotalAssets_ Whether to always compute total assets.
     */
    function setAlwaysComputeTotalAssets(bool alwaysComputeTotalAssets_)
        external
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _getVaultStorage().alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
        emit SetAlwaysComputeTotalAssets(alwaysComputeTotalAssets_);

        if (!alwaysComputeTotalAssets_) {
            _processAccounting();
        }
    }

    /**
     * @notice Returns whether the vault always computes total assets.
     * @return bool True if the vault always computes total assets.
     */
    function alwaysComputeTotalAssets() public view virtual returns (bool) {
        return _getVaultStorage().alwaysComputeTotalAssets;
    }

    /**
     * @notice Pauses the vault.
     */
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        if (paused()) {
            revert Paused();
        }

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        emit Pause(true);
    }

    /**
     * @notice Unpauses the vault.
     */
    function unpause() external virtual onlyRole(UNPAUSER_ROLE) {
        if (!paused()) {
            revert Unpaused();
        }

        VaultStorage storage vaultStorage = _getVaultStorage();
        if (provider() == address(0)) {
            revert ProviderNotSet();
        }
        vaultStorage.paused = false;
        emit Pause(false);
    }

    /**
     * @notice Processes the accounting of the vault by calculating the total base balance.
     * @dev This function iterates through the list of assets, gets their balances and rates,
     *      and updates the total assets denominated in the base asset.
     */
    function processAccounting() public virtual nonReentrant {
        _processAccounting();
    }

    function _processAccounting() internal virtual {
        uint256 totalBaseBalance = computeTotalAssets();

        _getVaultStorage().totalAssets = totalBaseBalance;
        // solhint-disable-next-line not-rely-on-time
        emit ProcessAccounting(block.timestamp, totalBaseBalance);
    }

    /**
     * @notice Computes the total assets in the vault.
     * @return totalBaseBalance The total assets in the vault.
     */
    function computeTotalAssets() public view virtual returns (uint256 totalBaseBalance) {
        totalBaseBalance = VaultLib.computeTotalAssets();
    }

    /**
     * @notice Processes a series of calls to target contracts.
     * @param targets The addresses of the target contracts.
     * @param values The values to send with the calls.
     * @param data The calldata for the calls.
     * @return returnData The return data from the calls.
     */
    function processor(address[] calldata targets, uint256[] memory values, bytes[] calldata data)
        external
        virtual
        onlyRole(PROCESSOR_ROLE)
        returns (bytes[] memory returnData)
    {
        return VaultLib.processor(targets, values, data);
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Fallback function to handle native asset transfers.
     */
    receive() external payable {
        emit NativeDeposit(msg.value);
    }

    /// FEES ///
    /**
     * @notice Returns the fee on raw assets where the fee would get added on top of the assets.
     * @param assets The amount of assets.
     * @return The fee on raw assets.
     */
    function _feeOnRaw(uint256 assets) public view virtual override returns (uint256);

    /**
     * @notice Returns the fee on total assets where the fee is already included.
     * @param assets The amount of assets.
     * @return The fee on total assets.
     */
    function _feeOnTotal(uint256 assets) public view virtual override returns (uint256);
}
