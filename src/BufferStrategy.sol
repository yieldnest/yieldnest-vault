// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "src/Common.sol";
import {BaseVault} from "src/BaseVault.sol";
import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract BufferStrategy is BaseStrategy {

    struct BufferStrategyStorage {
        address usdcCoreVault;
    }
    /// @notice Role for morpho usdc core vault manager permissions
    bytes32 public constant MORPHO_USDC_CORE_VAULT_MANAGER_ROLE = keccak256("MORPHO_USDC_CORE_VAULT_MANAGER_ROLE");
    
    /// @notice Role for deposit manager permissions
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");
    /**
     * @notice Initializes the Strategy Vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     */
    function initialize(address admin, string memory name, string memory symbol, uint8 decimals_)
        external
        initializer
    {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
    }

    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset convertion of shares.
     * @dev This is an example:
     *     The _deposit function for strategies needs an override
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal virtual override onlyAllocator {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += baseAssets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);

        if (_getSyncStrategyStorage().syncDeposit) {
            address usdcCoreVault = _getBufferStrategyStorage().usdcCoreVault;
            SafeERC20.safeIncreaseAllowance(IERC20(asset_), usdcCoreVault, assets);
            IERC4626(usdcCoreVault).deposit(assets, address(this));
        }

        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
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
        if (!_getBaseStrategyStorage().isAssetWithdrawable[asset_]) {
            revert AssetNotWithdrawable();
        }

        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

         uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        if (vaultBalance < assets && _getSyncStrategyStorage().syncWithdraw) {
            uint256 amountToWithdraw = assets - vaultBalance;
            address usdcCoreVault = _getBufferStrategyStorage().usdcCoreVault;
            IERC4626(usdcCoreVault).withdraw(amountToWithdraw, address(this), address(this));
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Internal function to get the maximum amount of assets that can be withdrawn by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view virtual override returns (uint256 maxAssets) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_); // decimals will be 6

        maxAssets = previewRedeemAsset(asset_, balanceOf(owner));

        maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
    }

     /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     */
    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));
        if (_getSyncStrategyStorage().syncWithdraw) {
            address usdcCoreVault = _getBufferStrategyStorage().usdcCoreVault;
            uint256 usdcCoreVaultBalance = IERC4626(usdcCoreVault).balanceOf(address(this));
            uint256 availableAssetsInUSDCVault = IERC4626(usdcCoreVault).previewRedeem(usdcCoreVaultBalance);
            availableAssets += availableAssetsInUSDCVault;
        }
    }

    /**
     * @notice Internal function to get the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function _maxRedeemAsset(address asset_, address owner) internal view virtual override returns (uint256 maxShares) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_);

        maxShares = balanceOf(owner);

        maxShares = availableAssets < previewRedeemAsset(asset_, maxShares)
            ? previewWithdrawAsset(asset_, availableAssets)
            : maxShares;
    }

     /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getSyncStrategyStorage() internal pure virtual returns (SyncStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.sync")
            $.slot := 0x023d1cf75a0b8417c3b567b13742795389a9b4d09bd3ca14ffeda95bbf3e6f7a
        }
    }

    function _getBufferStrategyStorage() internal pure virtual returns (BufferStrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy.buffer")
            $.slot := 0xfdc764d4e5946388ce23bfc295aa25f4722838debaa9bd7cf51f9c12ea870bf1
        }
    }

    function _feeOnRaw(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256) public pure override returns (uint256) {
        return 0;
    }

    function setUsdcCoreVault(address usdcCoreVault_) external onlyRole(MORPHO_USDC_CORE_VAULT_MANAGER_ROLE) {
        if (usdcCoreVault_ == address(0)) {
            revert ZeroAddress();
        }
        _getBufferStrategyStorage().usdcCoreVault = usdcCoreVault_;
    }

    /**
     * @notice Sets the sync deposit flag.
     * @param syncDeposit The new value for the sync deposit flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        _getSyncStrategyStorage().syncDeposit = syncDeposit;
    }

    /**
     * @notice Sets the sync withdraw flag.
     * @param syncWithdraw The new value for the sync withdraw flag.
     */
    function setSyncWithdraw(bool syncWithdraw) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        _getSyncStrategyStorage().syncWithdraw = syncWithdraw;
    }
}