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
import {IRateProvider} from "src/interface/IRateProvider.sol";

contract Vault is IVault, ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    function decimals() public view virtual override(ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        AssetStorage storage assetStorage = _getAssetStorage();
        return assetStorage.assets[assetStorage.list[0]].decimals;
    }

    function asset() public view returns (address) {
        return _getAssetStorage().list[0];
    }

    function totalAssets() public view returns (uint256) {
        return _getVaultStorage().totalAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxWithdraw(address owner) public view returns (uint256) {
        return _convertToAssets(asset(), balanceOf(owner), Math.Rounding.Floor);
    }

    // QUESTION: How to handle this in v1 with async withdraws.
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Ceil);
    }

    // QUESTION: How to handle this? Start disabled, come back later
    // This would have to be it's own Liquidity and Risk Module
    // that calculates the asset ratios and figure out the debt ratio
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(asset(), assets, Math.Rounding.Ceil);
    }

    // QUESTION: How do we handle this?
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(asset(), shares, Math.Rounding.Floor);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256) {
        if (paused()) revert Paused();

        uint256 shares = previewDeposit(assets);
        _deposit(asset(), _msgSender(), receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        if (paused()) revert Paused();

        uint256 assets_ = previewMint(shares);
        _deposit(asset(), _msgSender(), receiver, assets_, shares);

        return assets_;
    }

    // QUESTION: How to handle this in v1 if no sync withdraws
    function withdraw(uint256 assets_, address receiver, address owner) public returns (uint256) {
        // uint256 maxAssets = maxWithdraw(owner);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        // }

        // uint256 shares = previewWithdraw(assets);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return shares;
    }

    // QUESTION: How to handle this in v1 with async withdraws
    function redeem(uint256 shares_, address receiver, address owner) public returns (uint256) {
        // uint256 maxShares = maxRedeem(owner);
        // if (shares > maxShares) {
        //     revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        // }

        // uint256 assets = previewRedeem(shares);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return assets;
    }

    //// 4626-MAX ////

    function getAssets() public view returns (address[] memory) {
        return _getAssetStorage().list;
    }

    function getStrategies() public view returns (address[] memory) {
        return _getStrategyStorage().list;
    }

    function previewDepositAsset(address asset_, uint256 assets_) public view returns (uint256) {
        return _convertToShares(asset_, assets_, Math.Rounding.Floor);
    }

    function depositAsset(address asset_, uint256 assets_, address receiver) public returns (uint256) {
        if (paused()) revert Paused();

        uint256 shares = previewDepositAsset(asset_, assets_);
        _deposit(asset_, _msgSender(), receiver, assets_, shares);

        return shares;
    }

    function paused() public view returns (bool) {
        return _getVaultStorage().paused;
    }

    function rateProvider() public view returns (address) {
        return _getVaultStorage().rateProvider;
    }

    // QUESTION: What params should be used here? strategy, asset, etc.
    function processAccounting() external {
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
    //// INTERNAL ////

    function _convertToAssets(address asset_, uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 convertedShares = _convertBaseToAssets(asset_, shares);
        return convertedShares.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToShares(address asset_, uint256 assets_, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 convertedAssets = _convertAssetsToBase(asset_, assets_);
        return convertedAssets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertAssetsToBase(address asset_, uint256 amount) internal view returns (uint256) {
        uint256 rate = IRateProvider(_getVaultStorage().rateProvider).getRate(asset_);
        return amount * rate / 1e18;
    }

    function _convertBaseToAssets(address asset_, uint256 baseAmount) internal view returns (uint256) {
        uint256 rate = IRateProvider(_getVaultStorage().rateProvider).getRate(asset_);
        return baseAmount * 1e18 / rate;
    }

    /// @dev Being Multi asset, we need to add the asset param here to deposit the user's asset accordingly.
    function _deposit(address asset_, address caller, address receiver, uint256 assets, uint256 shares) internal {
        _getVaultStorage().totalAssets += assets;
        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    // QUESTION: How might we
    function _withdraw(address caller, address receiver, address owner, uint256 assetAmount, uint256 shares) internal {
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

    function _decimalsOffset() internal pure returns (uint8) {
        return 0;
    }

    function _getVaultStorage() internal pure returns (VaultStorage storage $) {
        assembly {
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }

    function _getAssetStorage() internal pure returns (AssetStorage storage $) {
        assembly {
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }

    function _getStrategyStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            $.slot := 0x36e313fea70c5f83d23dd12fc41865566e392cbac4c21baf7972d39f7af1774d
        }
    }

    //// ADMIN ////

    // QUESTION: Measure the gas difference between IERC20 or address when casting / saving to storage
    function setRateProvider(address rateProvider_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rateProvider_ == address(0)) revert ZeroAddress();
        _getVaultStorage().rateProvider = rateProvider_;
        emit SetRateProvider(rateProvider_);
    }

    function addAsset(address assetAddress, uint8 decimals_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (assetAddress == address(0)) revert ZeroAddress();

        AssetStorage storage assetStorage = _getAssetStorage();
        if (assetStorage.list.length > 0 && assetStorage.assets[assetAddress].index != 0) revert InvalidAsset();

        uint256 newIndex = assetStorage.list.length;
        assetStorage.assets[assetAddress] =
            AssetParams({active: true, index: newIndex, decimals: decimals_, idleAssets: 0, deployedAssets: 0});

        assetStorage.list.push(assetAddress);

        emit NewAsset(assetAddress, decimals_, newIndex);
    }

    function toggleAsset(address assetAddress, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetStorage storage assetStorage = _getAssetStorage();
        if (assetStorage.list[0] == address(0)) revert AssetNotFound();
        assetStorage.assets[assetAddress].active = active;
        emit ToggleAsset(assetAddress, active);
    }

    function addStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        if (strategy == address(0)) revert ZeroAddress();
        // TODO: Add check to make sure sum of all ratios not gt 10k

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        uint256 index = strategyStorage.list.length;

        if (index > 0 && strategyStorage.strategies[strategy].index != 0) {
            revert DuplicateStrategy();
        }

        strategyStorage.strategies[strategy] = StrategyParams({active: true, index: index, deployedAssets: 0});

        strategyStorage.list.push(strategy);

        emit NewStrategy(strategy, index);
        return true;
    }

    function pause(bool paused_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = paused_;
        emit Pause(paused_);
    }

    // QUESTION: Start with Strategies or add them later
    // vault starts paused because the rate provider and assets / strategies haven't been set
    function initialize(address admin, string memory name, string memory symbol) external initializer {
        // Initialize the vault
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
    }

    constructor() {
        _disableInitializers();
    }
}
