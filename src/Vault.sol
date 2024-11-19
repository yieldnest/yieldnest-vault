// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    AccessControlUpgradeable,
    Address,
    ERC20PermitUpgradeable,
    ERC20Upgradeable,
    IERC20,
    IERC20Metadata,
    Math,
    ReentrancyGuardUpgradeable,
    SafeERC20
} from "./Common.sol";

import {IVault} from "src/interface/IVault.sol";
import {IStrategy} from "src/interface/IStrategy.sol";
import {IRateProvider} from "src/interface/IRateProvider.sol";
import {Guard} from "src/module/Guard.sol";

contract Vault is IVault, ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    /**
     * @notice Returns the number of decimals of the underlying asset.
     * @return uint256 The number of decimals.
     */
    function decimals() public view virtual override(ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        AssetStorage storage assetStorage = _getAssetStorage();
        return assetStorage.assets[assetStorage.list[0]].decimals;
    }

    /**
     * @notice Returns the address of the underlying asset.
     * @return uint256 The address of the asset.
     */
    function asset() public view returns (address) {
        return _getAssetStorage().list[0];
    }

    /**
     * @notice Returns the total assets held by the vault denominated in the underlying asset.
     * @return uint256 The total assets.
     */
    function totalAssets() public view returns (uint256) {
        return _getVaultStorage().totalAssets;
    }

    /**
     * @notice Converts a given amount of assets to shares.
     * @param assets The amount of assets to convert.
     * @return uint256 The equivalent amount of shares.
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice Converts a given amount of shares to assets.
     * @param shares The amount of shares to convert.
     * @return uint256 The equivalent amount of assets.
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets.
     * @param assets The amount of assets to deposit.
     * @return uint256 The equivalent amount of shares.
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of assets that would be required to mint a given amount of shares.
     * @param shares The amount of shares to mint.
     * @return uint256 The equivalent amount of assets.
     */
    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of shares that would be required to withdraw a given amount of assets.
     * @param assets The amount of assets to withdraw.
     * @return uint256 The equivalent amount of shares.
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param shares The amount of shares to redeem.
     * @return uint256 The equivalent amount of assets.
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited by a given owner.
     * @param owner The address of the owner.
     * @return uint256 The maximum amount of assets.
     */
    function maxDeposit(address owner) public view returns (uint256) {
        if (paused()) {
            return 0;
        }
        return IERC20(asset()).balanceOf(owner);
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted.
     * @return uint256 The maximum amount of shares.
     */
    function maxMint(address) public view returns (uint256) {
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
    function maxWithdraw(address owner) public view returns (uint256) {
        if (paused()) {
            return 0;
        }
        uint256 baseConvertedAssets = _convertToAssets(asset(), balanceOf(owner), Math.Rounding.Floor);
        uint256 availableAssets = IStrategy(bufferStrategy()).maxWithdraw(address(this));
        if (availableAssets < baseConvertedAssets) {
            return 0;
        }
        return baseConvertedAssets;
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return uint256 The maximum amount of shares.
     */
    function maxRedeem(address owner) public view returns (uint256) {
        if (paused()) {
            return 0;
        }
        uint256 baseConvertedAssets = _convertToAssets(asset(), balanceOf(owner), Math.Rounding.Floor);
        uint256 availableAssets = IStrategy(bufferStrategy()).maxWithdraw(address(this));
        if (availableAssets < baseConvertedAssets) {
            return 0;
        }
        return baseConvertedAssets;
    }

    /**
     * @notice Deposits a given amount of assets and assigns the equivalent amount of shares to the receiver.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function deposit(uint256 assets, address receiver) public nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        uint256 shares = previewDeposit(assets);
        _deposit(asset(), _msgSender(), receiver, assets, shares);
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
        uint256 assets_ = previewMint(shares);
        _deposit(asset(), _msgSender(), receiver, assets_, shares);
        return assets_;
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return uint256 The equivalent amount of shares.
     */
    function withdraw(uint256 assets, address receiver, address owner) public nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        uint256 shares = previewWithdraw(assets);
        _withdraw(asset(), _msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @notice Redeems a given amount of shares and transfers the equivalent amount of assets to the receiver.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return uint256 The equivalent amount of assets.
     */
    function redeem(uint256 shares, address receiver, address owner) public nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(owner, shares, maxShares);
        }
        uint256 assets = previewRedeem(shares);
        _withdraw(asset(), _msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    //// 4626-MAX ////

    /**
     * @notice Returns the list of asset addresses.
     * @return addresses The list of asset addresses.
     */
    function getAssets() public view returns (address[] memory) {
        return _getAssetStorage().list;
    }

    /**
     * @notice Returns the parameters of a given asset.
     * @param asset_ The address of the asset.
     * @return AssetParams The parameters of the asset.
     */
    function getAsset(address asset_) public view returns (AssetParams memory) {
        return _getAssetStorage().assets[asset_];
    }

    /**
     * @notice Returns the list of strategy addresses.
     * @return addresses The list of strategy addresses.
     */
    function getStrategies() public view returns (address[] memory) {
        return _getStrategyStorage().list;
    }

    /**
     * @notice Returns the parameters of a given strategy.
     * @param asset_ The address of the strategy.
     * @return StrategyParams The parameters of the strategy.
     */
    function getStrategy(address asset_) public view returns (StrategyParams memory) {
        return _getStrategyStorage().strategies[asset_];
    }

    /**
     * @notice Returns the function rule for a given contract address and function signature.
     * @param contractAddress The address of the contract.
     * @param funcSig The function signature.
     * @return FunctionRule The function rule.
     */
    function getProcessorRule(address contractAddress, bytes4 funcSig) public view returns (FunctionRule memory) {
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
     * @notice Returns the address of the rate provider.
     * @return address The address of the rate provider.
     */
    function rateProvider() public view returns (address) {
        return _getVaultStorage().rateProvider;
    }

    /**
     * @notice Returns the address of the buffer strategy.
     * @return address The address of the buffer strategy.
     */
    function bufferStrategy() public view returns (address) {
        return _getVaultStorage().bufferStrategy;
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets for a specific asset.
     * @param asset_ The address of the asset.
     * @param assets_ The amount of assets to deposit.
     * @return uint256 The equivalent amount of shares.
     */
    function previewDepositAsset(address asset_, uint256 assets_) public view returns (uint256) {
        if (!getAsset(asset_).active) {
            revert InvalidAsset(asset_);
        }
        return _convertToShares(asset_, assets_, Math.Rounding.Floor);
    }

    /**
     * @notice Deposits a given amount of assets for a specific asset and assigns the equivalent amount of shares to the receiver.
     * @param asset_ The address of the asset.
     * @param assets_ The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function depositAsset(address asset_, uint256 assets_, address receiver) public nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        if (!getAsset(asset_).active) {
            revert InvalidAsset(asset_);
        }
        uint256 shares = previewDepositAsset(asset_, assets_);
        _deposit(asset_, _msgSender(), receiver, assets_, shares);
        return shares;
    }

    /**
     * @notice Processes the accounting for the vault.
     */
    function processAccounting() public {
        AssetStorage storage assetStorage = _getAssetStorage();
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        uint256 totalBaseBalance = 0;

        for (uint256 i = 0; i < assetStorage.list.length; i++) {
            address asset_ = assetStorage.list[i];
            uint256 idleBalance = IERC20(asset_).balanceOf(address(this));
            // Update idle balance only if it has changed
            if (assetStorage.assets[asset_].idleBalance != idleBalance) {
                assetStorage.assets[asset_].idleBalance = idleBalance;
            }

            totalBaseBalance += _convertAssetToBase(asset_, idleBalance);
        }

        for (uint256 i = 0; i < strategyStorage.list.length; i++) {
            address strategy = strategyStorage.list[i];
            uint256 idleBalance = IERC20(strategy).balanceOf(address(this));
            // Update idle balance only if it has changed
            if (strategyStorage.strategies[strategy].idleBalance != idleBalance) {
                strategyStorage.strategies[strategy].idleBalance = idleBalance;
            }

            totalBaseBalance += _convertAssetToBase(strategy, idleBalance);
        }

        _getVaultStorage().totalAssets = totalBaseBalance;
    }

    //// INTERNAL ////

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The equivalent amount of shares.
     */
    function _deposit(address asset_, address caller, address receiver, uint256 assets, uint256 shares) internal {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += assets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdraw(address asset_, address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
    {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= assets;
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        IStrategy(vaultStorage.bufferStrategy).withdraw(assets, address(this), address(this));

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to convert shares to assets.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to convert.
     * @param rounding The rounding direction.
     * @return uint256 The equivalent amount of assets.
     */
    function _convertToAssets(address asset_, uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 baseDenominatedShares = _convertAssetToBase(asset_, shares);
        return baseDenominatedShares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * @notice Internal function to convert assets to shares.
     * @param asset_ The address of the asset.
     * @param assets_ The amount of assets to convert.
     * @param rounding The rounding direction.
     * @return uint256 The equivalent amount of shares.
     */
    function _convertToShares(address asset_, uint256 assets_, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 convertedAssets = _convertAssetToBase(asset_, assets_);
        return convertedAssets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @notice Internal function to convert an asset amount to its base denomination.
     * @param asset_ The address of the asset.
     * @param amount The amount of the asset.
     * @return uint256 The equivalent amount in base denomination.
     */
    function _convertAssetToBase(address asset_, uint256 amount) internal view returns (uint256) {
        if (asset_ == address(0)) {
            revert ZeroAddress();
        }
        uint256 rate = IRateProvider(rateProvider()).getRate(asset_);
        return amount.mulDiv(rate, 10 ** getAsset(asset_).decimals, Math.Rounding.Floor);
    }

    /**
     * @notice Internal function to get the decimals offset.
     * @return uint8 The decimals offset.
     */
    function _decimalsOffset() internal pure returns (uint8) {
        return 0;
    }

    /**
     * @notice Internal function to get the vault storage.
     * @return $ The vault storage.
     */
    function _getVaultStorage() internal pure returns (VaultStorage storage $) {
        assembly {
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }

    /**
     * @notice Internal function to get the asset storage.
     * @return $ The asset storage.
     */
    function _getAssetStorage() internal pure returns (AssetStorage storage $) {
        assembly {
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }

    /**
     * @notice Internal function to get the strategy storage.
     * @return $ The strategy storage.
     */
    function _getStrategyStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            $.slot := 0x36e313fea70c5f83d23dd12fc41865566e392cbac4c21baf7972d39f7af1774d
        }
    }

    /**
     * @notice Internal function to get the processor storage.
     * @return $ The processor storage.
     */
    function _getProcessorStorage() internal pure returns (ProcessorStorage storage $) {
        assembly {
            $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
        }
    }

    //// ADMIN ////

    bytes32 public constant PROCESSOR_ROLE = 0xe61decff6e4a5c6b5a3d3cbd28f882e595173563b49353ce5f31dba2de7f05ee;

    /**
     * @notice Sets the rate provider.
     * @param rateProvider_ The address of the rate provider.
     */
    function setRateProvider(address rateProvider_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rateProvider_ == address(0)) {
            revert ZeroAddress();
        }
        _getVaultStorage().rateProvider = rateProvider_;
        emit SetRateProvider(rateProvider_);
    }

    /**
     * @notice Sets the buffer strategy.
     * @param bufferStrategy_ The address of the buffer strategy.
     */
    function setBufferStrategy(address bufferStrategy_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bufferStrategy_ == address(0)) {
            revert ZeroAddress();
        }
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (!strategyStorage.strategies[bufferStrategy_].active) {
            revert InvalidStrategy(bufferStrategy_);
        }
        _getVaultStorage().bufferStrategy = bufferStrategy_;
        emit SetBufferStrategy(bufferStrategy_);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule calldata rule)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _getProcessorStorage().rules[target][functionSig] = rule;
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param decimals_ The number of decimals of the asset.
     */
    function addAsset(address asset_, uint8 decimals_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (asset_ == address(0)) {
            revert ZeroAddress();
        }
        AssetStorage storage assetStorage = _getAssetStorage();
        uint256 index = assetStorage.list.length;
        if (index > 0 && assetStorage.assets[asset_].index != 0) {
            revert InvalidAsset(asset_);
        }
        assetStorage.assets[asset_] = AssetParams({active: true, index: index, decimals: decimals_, idleBalance: 0});
        assetStorage.list.push(asset_);
        emit NewAsset(asset_, decimals_, index);
    }

    /**
     * @notice Toggles the active status of an asset.
     * @param asset_ The address of the asset.
     * @param active The new active status.
     */
    function toggleAsset(address asset_, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetStorage storage assetStorage = _getAssetStorage();
        if (assetStorage.assets[asset_].decimals == 0) {
            revert InvalidAsset(asset_);
        }
        assetStorage.assets[asset_].active = active;
        emit ToggleAsset(asset_, active);
    }

    /**
     * @notice Adds a new strategy to the vault.
     * @param strategy The address of the strategy.
     * @param decimals_ The number of decimals of the strategy.
     */
    function addStrategy(address strategy, uint8 decimals_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (strategy == address(0)) {
            revert ZeroAddress();
        }
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        uint256 index = strategyStorage.list.length;

        if (index > 0 && strategyStorage.strategies[strategy].index != 0) {
            revert DuplicateStrategy();
        }

        strategyStorage.strategies[strategy] =
            StrategyParams({active: true, index: index, decimals: decimals_, idleBalance: 0});
        strategyStorage.list.push(strategy);
        emit NewStrategy(strategy, index);
    }

    /**
     * @notice Toggles the active status of a strategy.
     * @param strategy The address of the strategy.
     * @param active The new active status.
     */
    function toggleStrategy(address strategy, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (strategyStorage.strategies[strategy].decimals == 0) {
            revert InvalidStrategy(strategy);
        }
        strategyStorage.strategies[strategy].active = active;
        emit ToggleStrategy(strategy, active);
    }

    /**
     * @notice Pauses or unpauses the vault.
     * @param paused_ The new paused status.
     */
    function pause(bool paused_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        if (rateProvider() == address(0)) {
            revert RateProviderNotSet();
        }
        if (bufferStrategy() == address(0)) {
            revert BufferNotSet();
        }
        vaultStorage.paused = paused_;
        emit Pause(paused_);
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
        onlyRole(PROCESSOR_ROLE)
        returns (bytes[] memory returnData)
    {
        uint256 targetsLength = targets.length;
        returnData = new bytes[](targetsLength);

        for (uint256 i = 0; i < targetsLength; i++) {
            Guard.validateCall(targets[i], data[i]);

            (bool success, bytes memory returnData_) = targets[i].call{value: values[i]}(data[i]);
            if (!success) {
                revert ProcessFailed(data[i], returnData_);
            }
            returnData[i] = returnData_;
        }
        emit ProcessSuccess(targets, values, returnData);
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(address admin, string memory name, string memory symbol) external initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _getVaultStorage().paused = true;
    }

    constructor() {
        _disableInitializers();
    }

    // ETH //

    /**
     * @notice Internal function to mint shares for ETH.
     * @param amount The amount of ETH to deposit.
     */
    function _mintSharesForETH(uint256 amount) private {
        uint256 shares = previewDeposit(amount);
        (bool success,) = asset().call{value: amount}("");

        if (!success) {
            revert DepositFailed();
        }

        if (msg.sender != address(this)) {
            _mint(msg.sender, shares);
        }
        emit Deposit(msg.sender, msg.sender, amount, shares);
    }

    /**
     * @notice Fallback function to handle ETH deposits.
     */
    receive() external payable nonReentrant {
        if (msg.value > 0) {
            _mintSharesForETH(msg.value);
        }
    }
}
