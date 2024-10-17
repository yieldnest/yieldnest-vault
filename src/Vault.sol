// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {
    Address,
    IERC20,
    IVault,
    Math,
    IRateProvider,
    IERC20Metadata,
    SafeERC20,
    Storage,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable
} from "./Common.sol";

contract Vault is IVault, ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    function asset() public view virtual returns (address) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        return assetStorage.list[0];
    }

    function assets() public view returns (address[] memory assets_) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        uint256 assetListLength = assetStorage.list.length;
        assets_ = new address[](assetListLength);
        for (uint256 i = 0; i < assetListLength; i++) {
            assets_[i] = assetStorage.list[i];
        }
    }

    function decimals() public view virtual override(IERC20Metadata, ERC20PermitUpgradeable) returns (uint8) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        // QUESTION: Do we need this decimals offset?
        return assetStorage.assets[assetStorage.list[0]].decimals + _decimalsOffset();
    }

    function totalAssets() public view virtual returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        return vaultStorage.totalAssets;
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        return _convertToAssets(assetStorage.list[0], balanceOf(owner), Math.Rounding.Floor);
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxRedeem(address owner) public view virtual returns (uint256) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        return assetStorage.list[0].balanceOf(owner);
    }

    function previewDeposit(uint256 assetAmount) public view virtual returns (uint256) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        return _convertToShares(assetStorage.list[0], assetAmount, Math.Rounding.Floor);
    }

    function previewDepositAsset(address assetAddress, uint256 assetAmount) public view virtual returns (uint256) {
        return _convertToShares(assetAddress, assetAmount, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        return _convertToAssets(vaultStorage.asset, shares, Math.Rounding.Ceil);
    }

    function previewMintAsset(address assetAddress, uint256 shareAmount) public view virtual returns (uint256) {
        return _convertToAssets(assetAddress, shareAmount, Math.Rounding.Ceil);
    }

    // QUESTION: How to handle this? Start disabled, come back later
    // This would have to be it's own Liquidity and Risk Module
    // that calculates the asset ratios and figure out the debt ratio
    function previewWithdraw(uint256 assetAmount) public view virtual returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        return _convertToShares(vaultStorage.asset, assetAmount, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev See {IERC4626-deposit}.
     */
    function deposit(uint256 assetAmount, address receiver) public virtual returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        if (vaultStorage.paused) revert Paused();

        uint256 maxAssets = maxDeposit(receiver);
        if (assetAmount > maxAssets) {
            revert ExceededMaxDeposit(receiver, assetAmount, maxAssets);
        }

        uint256 shares = previewDeposit(assetAmount);
        _deposit(vaultStorage.asset, _msgSender(), receiver, assetAmount, shares);

        return shares;
    }

    /**
     * @dev See {IAssetVault-depositAsset}.
     */
    function depositAsset(address assetAddress, uint256 amount, address receiver) public virtual returns (uint256) {
        // uint256 maxAssets = maxDeposit(receiver);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        // }

        // uint256 shares = previewDeposit(assets);
        // _deposit(_msgSender(), receiver, assets, shares);

        // return shares;
    }

    /**
     * @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
     * In this case, the shares will be minted without requiring any assets to be deposited.
     */
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        // uint256 maxShares = maxMint(receiver);
        // if (shares > maxShares) {
        //     revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        // }

        // uint256 assets = previewMint(shares);
        // _deposit(_msgSender(), receiver, assets, shares);

        // return assets;
    }

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(uint256 assetAmount, address receiver, address owner) public virtual returns (uint256) {
        // uint256 maxAssets = maxWithdraw(owner);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        // }

        // uint256 shares = previewWithdraw(assets);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        // uint256 maxShares = maxRedeem(owner);
        // if (shares > maxShares) {
        //     revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        // }

        // uint256 assets = previewRedeem(shares);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return assets;
    }

    /**
     * @dev Converts assets to shares with support for rounding direction.
     *
     * This function first converts the assets to a base asset value using `_convertAssetToBase`, then scales this value
     * based on the total supply and total assets of the vault, with the option to round up or down.
     *
     * @param asset The address of the asset to convert.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction to use for the conversion.
     * @return The converted share value.
     */
    function _convertToShares(address assetAddress, uint256 assetAmount, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 convertedAssets = _convertAssetsToBase(assetAddress, assetAmount);
        return convertedAssets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertAssetsToBase(address assetAddress, uint256 assetAmount) internal view returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        uint256 rate = IRateProvider(vaultStorage).rateProvider.getRate(assetAddress);
        return (assetAmount * rate) / 1e18;
    }

    /**
     * @dev Converts shares to assets with support for rounding direction.
     *
     * This function takes an asset address, a number of shares, and a rounding direction as input.
     * It first converts the shares to a base asset value using `_convertBaseToAssets`, then scales this value
     * based on the total supply and total assets of the vault, with the option to round up or down.
     *
     * @param asset The address of the asset to convert shares to.
     * @param shares The number of shares to convert.
     * @param rounding The rounding direction to use for the conversion.
     * @return The converted asset value.
     */
    function _convertToAssets(address assetAddress, uint256 shareAmount, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 convertedAssets = _convertBaseToAssets(assetAddress, shareAmount);
        return convertedAssets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertBaseToAssets(address assetAddress, uint256 baseAmount) internal view returns (uint256) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        uint256 rate = IRateProvider(vaultStorage.rateProvider).getRate(assetAddress);
        return (baseAmount * 1e18) / rate;
    }

    /**
     * @dev Being Multi asset, we need to add the asset param here to deposit the user's asset accordingly.
     */
    function _deposit(address assetAddress, address caller, address receiver, uint256 assetAmount, uint256 shares)
        internal
        virtual
    {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        vaultStorage.totalAssets += _convertAssetsToBase(assetAddress, assetAmount);
        SafeERC20.safeTransferFrom(assetAddress, caller, address(this), assetAmount);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assetAmount, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assetAmount, uint256 shares)
        internal
        virtual
    {
        // ERC4626Storage storage $ = _getERC4626Storage();
        // if (caller != owner) {
        //     _spendAllowance(owner, caller, shares);
        // }

        // // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // // calls the vault, which is assumed not malicious.
        // //
        // // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // // shares are burned and after the assets are transferred, which is a valid state.
        // _burn(owner, shares);
        // SafeERC20.safeTransfer($._asset, receiver, assets);

        // emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    // Admin functions

    // QUESTION: Start with Strategies or add them later
    // vault starts paused because the rate provider and assets / strategies haven't been set
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        // Initialize the vault
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        vaultStorage.paused = true;
    }

    // QUESTION: Measure the gas difference between IERC20 or address when casting / saving to storage
    function setRateProvider(address rateProvider) public onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        vaultStorage.rateProvider = rateProvider;
        emit SetRateProvider(rateProvider);
    }

    function addAsset(address assetAddress, uint256 assetDecimals) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assetAddress == address(0)) revert ZeroAddress();
        if (assetDecimals > 18) revert InvalidDecimals();

        AssetStorage storage assetStorage = Storage._getAssetStorage();
        if (assetStorage.assets[assetAddress].asset != address(0)) revert InvalidAsset();

        uint256 newIndex = assetStorage.list.length;

        assetStorage.assets[assetAddress] = AssetParams({
            asset: assetAddress,
            active: true,
            index: newIndex,
            decimals: assetDecimals,
            idleAssets: 0,
            deployedAssets: 0
        });

        assetStorage.list.push(assetAddress);

        emit AddAsset(assetAddress, assetDecimals, newIndex);
    }

    function toggleAsset(address asset_, bool active) public onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetStorage storage assetStorage = Storage._getAssetStorage();
        if (assetStorage.assets[asset_].asset == address(0)) revert AssetNotFound();
        assetStorage.assets[asset_].active = active;
        emit ToggleAsset(asset_, active);
    }

    function pause(bool paused) public onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = Storage._getVaultStorage();
        vaultStorage.paused = paused;
        emit Pause(paused);
    }

    // QUESTION: What params should be used here? strategy, asset, etc.
    function processAccounting() public {
        // get the balances of the assets
        // AssetStorage storage assetStorage = _getAssetStorage();

        // for (uint256 i = 0; i < assetsStorage.list.length; i++) {
        //     address asset = assets[i];
        //     idleBalance = asset.balanceOf(address(vault));
        // }
        // get the balances of the strategies

        // call convertToAssets on the strategie?

        // QUESTION: Keep the balances for the assets, or keep that balances in base price

        // NOTE: Get the loops out of the public calls

        //yv3
        // what if you want to udpate a single strategy, but what if you want to update one strat
        // the debt value is used to separate the deposited value, you know what the rewards
        // balance is based on the the debt less the the rewards.
        // allows you to not have to grind through everything??
    }

    constructor() {
        _disableInitializers();
    }
}
