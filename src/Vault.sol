// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {
    Address,
    IERC20,
    Math,
    IERC20,
    IERC20Metadata,
    SafeERC20,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable
} from "./Common.sol";

import {Storage} from "src/Storage.sol";
import {IRateProvider} from "src/interface/IRateProvider.sol";
import {IVault} from "src/interface/IVault.sol";

contract Vault is IVault, ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    function asset() public view returns (address) {
        return Storage.getBaseAsset();
    }

    function assets() public view returns (address[] memory assets_) {
        return Storage.getAllAssets();
    }

    function decimals() public view virtual override returns (uint8) {
        return Storage.getBaseDecimals();
    }

    function totalAssets() public view returns (uint256) {
        return Storage.getTotalAssets();
    }

    function paused() public view returns (bool) {
        return Storage.getPaused();
    }

    function rateProvider() public view returns (address) {
        return Storage.getRateProvider();
    }

    function maxDeposit(address) public pure returns (uint256) {
        return Storage.getMaxDeposit();
    }

    function maxMint(address) public pure returns (uint256) {
        return Storage.getMaxMint();
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxWithdraw(address owner) public view returns (uint256) {
        return Storage.convertToAssets(asset(), balanceOf(owner), Math.Rounding.Floor);
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxRedeem(address owner) public view returns (uint256) {
        return IERC20(asset()).balanceOf(owner);
    }

    function previewDeposit(uint256 assets_) public view returns (uint256) {
        return Storage.convertToShares(asset(), assets_, Math.Rounding.Floor);
    }

    function previewDepositAsset(address asset_, uint256 assets_) public view returns (uint256) {
        return Storage.convertToShares(asset_, assets_, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares_) public view returns (uint256) {
        return Storage.convertToAssets(asset(), shares_, Math.Rounding.Ceil);
    }

    function previewMintAsset(address asset_, uint256 shares_) public view returns (uint256) {
        return Storage.convertToAssets(asset_, shares_, Math.Rounding.Ceil);
    }

    function convertToShares(uint256 assets_) public view returns (uint256) {
        return Storage.convertToShares(asset(), assets_, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return Storage.convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    // QUESTION: How to handle this? Start disabled, come back later
    // This would have to be it's own Liquidity and Risk Module
    // that calculates the asset ratios and figure out the debt ratio
    function previewWithdraw(uint256 assets_) public view returns (uint256) {
        return Storage.convertToShares(asset(), assets_, Math.Rounding.Ceil);
    }

    // QUESTION: How do we handle this?
    function previewRedeem(uint256 shares_) public view returns (uint256) {
        return Storage.convertToAssets(asset(), shares_, Math.Rounding.Floor);
    }

    function deposit(uint256 assets_, address receiver) public returns (uint256) {
        if (paused()) revert Paused();

        uint256 shares = previewDeposit(assets_);
        _deposit(asset(), _msgSender(), receiver, assets_, shares);

        return shares;
    }

    function depositAsset(address asset_, uint256 assets_, address receiver) public returns (uint256) {
        if (paused()) revert Paused();

        uint256 shares = previewDepositAsset(asset_, assets_);
        _deposit(asset_, _msgSender(), receiver, assets_, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        if (paused()) revert Paused();

        uint256 assets_ = previewMint(shares);
        _deposit(asset(), _msgSender(), receiver, assets_, shares);

        return assets_;
    }

    // QUESTION: How to handle this in v1 if no sync withdraws
    function withdraw(uint256 assets_, address receiver, address owner) public virtual returns (uint256) {
        // uint256 maxAssets = maxWithdraw(owner);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        // }

        // uint256 shares = previewWithdraw(assets);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return shares;
    }

    // QUESTION: How to handle this in v1 with async withdraws
    function redeem(uint256 shares_, address receiver, address owner) public virtual returns (uint256) {
        // uint256 maxShares = maxRedeem(owner);
        // if (shares > maxShares) {
        //     revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        // }

        // uint256 assets = previewRedeem(shares);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return assets;
    }

    /// @dev Being Multi asset, we need to add the asset param here to deposit the user's asset accordingly.
    function _deposit(address asset_, address caller, address receiver, uint256 assets_, uint256 shares)
        internal
        virtual
    {
        VaultStorage storage vaultStorage = Storage.getVaultStorage();
        vaultStorage.totalAssets += Storage.convertAssetsToBase(asset_, assets_);
        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets_);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets_, shares);
    }

    // QUESTION: How might we
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

    // QUESTION: Start with Strategies or add them later
    // vault starts paused because the rate provider and assets / strategies haven't been set
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        // Initialize the vault
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = Storage.getVaultStorage();
        vaultStorage.paused = true;
    }

    // QUESTION: Measure the gas difference between IERC20 or address when casting / saving to storage
    function setRateProvider(address rateProvider_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = Storage.getVaultStorage();
        vaultStorage.rateProvider = rateProvider_;
        emit SetRateProvider(rateProvider_);
    }

    function addAsset(address asset_, uint8 decimals_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (asset_ == address(0)) revert ZeroAddress();
        if (decimals_ > 18) revert InvalidDecimals();

        AssetStorage storage assetStorage = Storage.getAssetStorage();

        if (assetStorage.assets[asset_].decimals != 0) revert InvalidAsset();

        uint256 newIndex = assetStorage.list.length;

        assetStorage.assets[asset_] =
            AssetParams({active: true, index: newIndex, decimals: decimals_, idleAssets: 0, deployedAssets: 0});

        assetStorage.list.push(asset_);

        emit AddAsset(asset_, decimals_, newIndex);
    }

    function toggleAsset(address asset_, bool active) public onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetStorage storage assetStorage = Storage.getAssetStorage();
        if (assetStorage.assets[asset_].decimals == 0) revert AssetNotFound();
        assetStorage.assets[asset_].active = active;
        emit ToggleAsset(asset_, active);
    }

    function pause(bool paused_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = Storage.getVaultStorage();
        vaultStorage.paused = paused_;
        emit Pause(paused_);
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
