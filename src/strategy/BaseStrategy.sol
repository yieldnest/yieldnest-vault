// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20Metadata as IERC20, Math, SafeERC20} from "src/Common.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IBaseStrategy} from "src/interface/IBaseStrategy.sol";

/**
 * @title BaseStrategy
 * @author Yieldnest
 * @notice This contract is a base strategy for any underlying protocol.
 * vault.
 */
abstract contract BaseStrategy is BaseVault, IBaseStrategy {
    /// @notice The version of the strategy contract.
    string public constant STRATEGY_VERSION = "0.2.0";
    /// @notice Role for allocator permissions
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    /// @notice Role for allocator manager permissions
    bytes32 public constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");

    /**
     * @notice Returns whether the strategy has allocators.
     * @return hasAllocators True if the strategy has allocators, otherwise false.
     */
    function getHasAllocator() public view returns (bool hasAllocators) {
        return _getBaseStrategyStorage().hasAllocators;
    }

    /**
     * @notice Sets whether the strategy has allocators.
     * @param hasAllocators_ The new value for the hasAllocator flag.
     */
    function setHasAllocator(bool hasAllocators_) external onlyRole(ALLOCATOR_MANAGER_ROLE) {
        BaseStrategyStorage storage strategyStorage = _getBaseStrategyStorage();
        strategyStorage.hasAllocators = hasAllocators_;

        emit SetHasAllocator(hasAllocators_);
    }

    /**
     * @notice Returns whether the asset is withdrawable.
     * @param asset_ The address of the asset.
     * @return True if the asset is withdrawable, otherwise false.
     */
    function getAssetWithdrawable(address asset_) external view returns (bool) {
        return _getBaseStrategyStorage().isAssetWithdrawable[asset_];
    }

    /**
     * @notice Sets whether the asset is withdrawable.
     * @param asset_ The address of the asset.
     * @param withdrawable_ The new value for the withdrawable flag.
     */
    function setAssetWithdrawable(address asset_, bool withdrawable_) external onlyRole(ASSET_MANAGER_ROLE) {
        _setAssetWithdrawable(asset_, withdrawable_);
    }

    /**
     * @notice Internal function to set whether the asset is withdrawable.
     * @param asset_ The address of the asset.
     * @param withdrawable_ The new value for the withdrawable flag.
     */
    function _setAssetWithdrawable(address asset_, bool withdrawable_) internal {
        BaseStrategyStorage storage strategyStorage = _getBaseStrategyStorage();
        strategyStorage.isAssetWithdrawable[asset_] = withdrawable_;

        emit SetAssetWithdrawable(asset_, withdrawable_);
    }

    /**
     * @notice Modifier to restrict access to allocator roles.
     */
    modifier onlyAllocator() {
        if (_getBaseStrategyStorage().hasAllocators && !hasRole(ALLOCATOR_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, ALLOCATOR_ROLE);
        }
        _;
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn for a specific asset by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdrawAsset(address asset_, address owner) public view returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of assets that can be withdrawn by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
        if (paused() || !_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_);

        maxAssets = previewRedeemAsset(asset_, balanceOf(owner));

        maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeemAsset(address asset_, address owner) public view returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function _maxRedeemAsset(address asset_, address owner) internal view virtual returns (uint256 maxShares) {
        if (paused() || !_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_);

        maxShares = balanceOf(owner);

        maxShares = availableAssets < previewRedeemAsset(asset_, maxShares)
            ? previewWithdrawAsset(asset_, availableAssets)
            : maxShares;
    }

    /**
     * @notice Previews the amount of assets that would be required to mint a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to mint.
     * @return assets The equivalent amount of assets.
     */
    function previewMintAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
        assets = assets - _feeOnTotal(assets);
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewWithdrawAsset(address asset_, uint256 assets) public view virtual returns (uint256 shares) {
        uint256 fee = _feeOnRaw(assets);
        (shares,) = _convertToShares(asset_, assets + fee, Math.Rounding.Ceil);
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
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset(), assets, receiver, owner);
    }

    /**
     * @notice Withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset_, assets, receiver, owner);
    }

    /**
     * @notice Internal function for withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function _withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        internal
        returns (uint256 shares)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdrawAsset(asset_, owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = previewWithdrawAsset(asset_, assets);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
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
        override
    {
        _withdrawAsset(asset(), caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals for specific assets.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual onlyAllocator {
        if (!_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            revert AssetNotWithdrawable();
        }

        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
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
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset(), shares, receiver, owner);
    }

    /**
     * @notice Redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset_, shares, receiver, owner);
    }

    /**
     * @notice Internal function for redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function _redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        internal
        returns (uint256 assets)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeemAsset(asset_, owner);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = previewRedeemAsset(asset_, shares);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset conversion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal virtual override onlyAllocator {
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getBaseStrategyStorage() internal pure virtual returns (BaseStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.base")
            $.slot := 0x5cfdf694cb3bdee9e4b3d9c4b43849916bf3f018805254a1c0e500548c668500
        }
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param decimals_ The decimals of the asset.
     * @param depositable_ Whether the asset is depositable.
     * @param withdrawable_ Whether the asset is withdrawable.
     */
    function addAsset(address asset_, uint8 decimals_, bool depositable_, bool withdrawable_)
        public
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAsset(asset_, decimals_, depositable_);
        _setAssetWithdrawable(asset_, withdrawable_);
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param depositable_ Whether the asset is depositable.
     * @param withdrawable_ Whether the asset is withdrawable.
     */
    function addAsset(address asset_, bool depositable_, bool withdrawable_)
        external
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAsset(asset_, IERC20(asset_).decimals(), depositable_);
        _setAssetWithdrawable(asset_, withdrawable_);
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     * @dev This function is used to calculate the available assets for a given asset,
     *      It returns the balance of the asset in the vault and also adds any assets
     *      already staked in an underlying staking protocol that is available for withdrawal.
     */
    function _availableAssets(address asset_) internal view virtual returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));
    }
}
