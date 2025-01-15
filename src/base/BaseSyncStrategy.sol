// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "src/Common.sol";
import {BaseStrategy} from "src/base/BaseStrategy.sol";

import {StrategyLib} from "src/libraries/StrategyLib.sol";

/**
 * @title BaseSyncStrategy
 * @author Yieldnest
 * @notice This contract is a base strategy for any underlying protocol with syncDeposit and syncWithdraw flags.
 * vault.
 */
abstract contract BaseSyncStrategy is BaseStrategy {
    /// @notice Emitted when the sync deposit flag is set
    event SetSyncDeposit(bool syncDeposit);

    /// @notice Emitted when the sync withdraw flag is set
    event SetSyncWithdraw(bool syncWithdraw);

    /**
     * @notice Returns the current sync deposit flag.
     * @return syncDeposit The sync deposit flag.
     */
    function getSyncDeposit() public view returns (bool syncDeposit) {
        return _getSyncStrategyStorage().syncDeposit;
    }

    /**
     * @notice Returns the current sync withdraw flag.
     * @return syncWithdraw The sync withdraw flag.
     */
    function getSyncWithdraw() public view returns (bool syncWithdraw) {
        return _getSyncStrategyStorage().syncWithdraw;
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

        if (_getSyncStrategyStorage().syncDeposit) {
            _stake(asset_, assets);
        }
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
    ) internal virtual override onlyAllocator {
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        if (vaultBalance < assets && _getSyncStrategyStorage().syncWithdraw) {
            _unstake(asset_, assets - vaultBalance);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return The strategy storage structure.
     */
    function _getSyncStrategyStorage() internal pure virtual returns (StrategyLib.SyncStrategyStorage storage) {
        return StrategyLib.getSyncStrategyStorage();
    }

    /**
     * @notice Sets the sync deposit flag.
     * @param syncDeposit The new value for the sync deposit flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(StrategyLib.DEPOSIT_MANAGER_ROLE) {
        StrategyLib.SyncStrategyStorage storage strategyStorage = _getSyncStrategyStorage();
        strategyStorage.syncDeposit = syncDeposit;

        emit SetSyncDeposit(syncDeposit);
    }

    /**
     * @notice Sets the sync withdraw flag.
     * @param syncWithdraw The new value for the sync withdraw flag.
     */
    function setSyncWithdraw(bool syncWithdraw) external onlyRole(StrategyLib.DEPOSIT_MANAGER_ROLE) {
        StrategyLib.SyncStrategyStorage storage strategyStorage = _getSyncStrategyStorage();
        strategyStorage.syncWithdraw = syncWithdraw;

        emit SetSyncWithdraw(syncWithdraw);
    }

    /**
     * @notice Internal function to unstake assets from underlying staking protocol.
     * @param asset_ The address of the asset to unstake.
     * @param amount The amount of assets to unstake.
     * @dev This function must increase the balance of the asset in the vault by the amount of assets unstaked.
     */
    function _unstake(address asset_, uint256 amount) internal virtual;

    /**
     * @notice Internal function to stake assets into the underlying staking protocol
     * @param asset_ The address of the asset to stake
     * @param assets The amount of assets to stake
     * @dev This function must decrease the balance of the asset in the vault by the amount of assets staked.
     */
    function _stake(address asset_, uint256 assets) internal virtual;
}
