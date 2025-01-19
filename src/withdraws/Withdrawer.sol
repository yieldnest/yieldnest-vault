// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {IERC20Metadata} from "src/Common.sol";
import {AsyncWithdrawLib} from "src/library/AsyncWithdrawLib.sol";

contract Withdrawer is BaseStrategy {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
        _initialize(admin, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
    }

    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        return AsyncWithdrawLib.computeTotalAssets();
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    function asyncWithdrawBalance(address asset, address /*owner*/ ) external view returns (uint256, uint256) {
        return AsyncWithdrawLib.asyncWithdrawBalance(asset, address(this));
    }

    /**
     * @notice Adds a new Async asset to the vault.
     * @param asset_ The address of the asset.
     * @param withdrawalQueueManager The address of the withdrawal queue manager.
     * @param depositable_ Whether the asset is depositable.
     * @param withdrawable_ Whether the asset is withdrawable.
     */
    function addAsyncAsset(address asset_, address withdrawalQueueManager, bool depositable_, bool withdrawable_)
        external
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAsset(asset_, IERC20Metadata(asset_).decimals(), depositable_);
        _setAssetWithdrawable(asset_, withdrawable_);
        AsyncWithdrawLib.addAsyncAsset(asset_, withdrawalQueueManager);
    }

    function isAsyncAsset(address asset_) public view returns (bool) {
        return AsyncWithdrawLib.isAsyncAsset(asset_);
    }

    function _getWithdrawerStorage() internal view returns (AsyncWithdrawLib.WithdrawerStorage storage) {
        return AsyncWithdrawLib.getWithdrawerStorage();
    }
}
