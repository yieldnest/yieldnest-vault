pragma solidity ^0.8.0;

import "../BaseVault.sol";

import {IERC4626} from "src/Common.sol";

contract ERC4626Allocator is BaseVault {
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    error InsufficientAssetsInVaults();
    error AssetIsDefault();
    error UnderlyingAssetMismatch(address vaultUnderlying, address allocatorUnderlying);

    address[] public vaults;

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals_ The number of decimals for the vault token.
     * @param countNativeAsset_ Whether the vault should count the native asset.
     * @param alwaysComputeTotalAssets_ Whether the vault should always compute total assets.
     * @param defaultAssetIndex_ The index of the default asset in the asset list.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external virtual initializer {
        _initialize(
            admin, // Address with admin privileges for the vault
            name, // Name of the vault token (ERC20)
            symbol, // Symbol of the vault token (ERC20)
            decimals_, // Decimal precision for the vault token
            true, // Start the vault in paused state for safety
            countNativeAsset_, // Whether to include native ETH in asset calculations
            alwaysComputeTotalAssets_, // Whether to compute assets in real-time vs using cached values
            defaultAssetIndex_ // Index of the default asset in the asset list
        );
    }

    /**
     * @notice Sets the vaults to be used for allocation.
     * @param _vaults The array of vault addresses.
     * @dev Each vault must be a registered asset in the vault.
     */
    function setVaults(address[] calldata _vaults) public onlyRole(VAULT_MANAGER_ROLE) {
        for (uint256 i = 0; i < _vaults.length; i++) {
            address vault = _vaults[i];
            IVault.AssetParams memory assetParams = _getAssetStorage().assets[vault];
            if (assetParams.decimals == 0) {
                revert InvalidAsset(vault);
            }
            if (vault == asset()) {
                revert AssetIsDefault();
            }

            if (IERC4626(vault).asset() != asset()) {
                revert UnderlyingAssetMismatch(vault, asset());
            }
        }
        vaults = _vaults;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        uint256 baseAssets = VaultLib.convertAssetToBase(asset(), assets);

        _subTotalAssets(baseAssets);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        (address[] memory planVaults, uint256[] memory planAmounts) = generateWithdrawalPlan(assets);

        for (uint256 i = 0; i < planVaults.length; i++) {
            IERC4626(planVaults[i]).withdraw(planAmounts[i], receiver, address(this));
        }

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Generates a withdrawal plan for the given amount of assets.
     *      Default implementation is FIFO: withdraw from the first vaults in order until satisfied.
     * @param assets The total amount of assets to withdraw.
     * @return planVaults The vaults to withdraw from.
     * @return planAmounts The amounts to withdraw from each vault.
     */
    function generateWithdrawalPlan(uint256 assets)
        public
        view
        virtual
        returns (address[] memory planVaults, uint256[] memory planAmounts)
    {
        planVaults = new address[](vaults.length);
        planAmounts = new uint256[](vaults.length);

        uint256 remaining = assets;
        uint256 planCount = 0;

        for (uint256 i = 0; i < vaults.length && remaining > 0; i++) {
            uint256 maxWithdrawable = IERC4626(vaults[i]).maxWithdraw(address(this));
            if (maxWithdrawable == 0) continue;

            uint256 withdrawAmount = maxWithdrawable >= remaining ? remaining : maxWithdrawable;
            planVaults[planCount] = vaults[i];
            planAmounts[planCount] = withdrawAmount;
            planCount++;
            remaining -= withdrawAmount;
        }

        if (remaining != 0) {
            revert InsufficientAssetsInVaults();
        }

        // Resize arrays to actual planCount
        assembly {
            mstore(planVaults, planCount)
            mstore(planAmounts, planCount)
        }
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (paused()) {
            return 0;
        }

        uint256 bufferAssets = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            bufferAssets += IERC4626(vaults[i]).maxWithdraw(address(this));
        }

        if (bufferAssets == 0) {
            return 0;
        }

        uint256 ownerShares = balanceOf(owner);
        uint256 maxAssets = previewRedeem(ownerShares);

        return bufferAssets < maxAssets ? bufferAssets : maxAssets;
    }

    /// FEES ///
    /// @inheritdoc BaseVault
    function _feeOnRaw(uint256 /* assets */ ) public view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc BaseVault
    function _feeOnTotal(uint256 /* assets */ ) public view virtual override returns (uint256) {
        return 0;
    }
}
