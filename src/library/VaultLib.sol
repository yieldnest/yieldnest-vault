// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {Math, IERC20} from "src/Common.sol";
import {Guard} from "src/module/Guard.sol";

library VaultLib {
    using Math for uint256;

    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20
    struct ERC20Storage {
        mapping(address account => uint256) balances;
        mapping(address account => mapping(address spender => uint256)) allowances;
        uint256 totalSupply;
        string name;
        string symbol;
    }

    /**
     * @notice Get the ERC20 storage.
     * @return $ The ERC20 storage.
     */
    function getERC20Storage() public pure returns (ERC20Storage storage $) {
        assembly {
            // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00
        }
    }

    /**
     * @notice Get the vault storage.
     * @return $ The vault storage.
     */
    function getVaultStorage() public pure returns (IVault.VaultStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.vault")
            $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
        }
    }

    /**
     * @notice Get the asset storage.
     * @return $ The asset storage.
     */
    function getAssetStorage() public pure returns (IVault.AssetStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.asset")
            $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
        }
    }

    /**
     * @notice Get the processor storage.
     * @return $ The processor storage.
     */
    function getProcessorStorage() public pure returns (IVault.ProcessorStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.vault")
            $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
        }
    }

    /**
     * @notice Get the fee storage.
     * @return $ The fee storage.
     */
    function getFeeStorage() public pure returns (IVault.FeeStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.fees")
            $.slot := 0xde924653ae91bd33356774e603163bd5862c93462f31acccae5f965be6e6599b
        }
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param active_ Whether the asset is active or not.
     */
    function addAsset(address asset_, uint8 decimals_, bool active_) public {
        if (asset_ == address(0)) {
            revert IVault.ZeroAddress();
        }

        IVault.AssetStorage storage assetStorage = getAssetStorage();
        uint256 index = assetStorage.list.length;

        if (index == 0 && getVaultStorage().countNativeAsset && decimals_ != 18) {
            // if native asset is counted the primary asset should match the decimals count.
            revert IVault.InvalidNativeAssetDecimals(decimals_);
        }

        if (index > 0 && assetStorage.assets[asset_].index != 0) {
            revert IVault.DuplicateAsset(asset_);
        }
        assetStorage.assets[asset_] = IVault.AssetParams({active: active_, index: index, decimals: decimals_});
        assetStorage.list.push(asset_);

        emit IVault.NewAsset(asset_, decimals_, index);
    }

    /**
     * @notice Updates an existing asset's parameters in the vault.
     * @param index The index of the asset to update.
     * @param fields The AssetUpdateFields struct containing the updated fields.
     */
    function updateAsset(uint256 index, IVault.AssetUpdateFields calldata fields) public {
        IVault.AssetStorage storage assetStorage = getAssetStorage();
        if (index >= assetStorage.list.length) {
            revert IVault.InvalidAsset(address(0));
        }

        address asset_ = assetStorage.list[index];
        IVault.AssetParams storage assetParams = assetStorage.assets[asset_];
        assetParams.active = fields.active;
        emit IVault.UpdateAsset(index, asset_, fields);
    }

    /**
     * @notice Deletes an existing asset from the vault.
     * @param index The index of the asset to delete.
     */
    function deleteAsset(uint256 index) public {
        if (index == 0) revert IVault.DefaultAsset();
        IVault.AssetStorage storage assetStorage = getAssetStorage();
        if (index >= assetStorage.list.length) {
            revert IVault.InvalidAsset(address(0));
        }
        address asset_ = assetStorage.list[index];
        if (IERC20(asset_).balanceOf(address(this)) > 0) {
            revert IVault.AssetNotEmpty(asset_);
        }

        assetStorage.list[index] = assetStorage.list[assetStorage.list.length - 1];
        assetStorage.list.pop();
        delete assetStorage.assets[asset_];
        emit IVault.DeleteAsset(index, asset_);
    }

    /**
     * @notice Converts an asset amount to base units.
     * @param asset_ The address of the asset.
     * @param assets The amount of the asset.
     * @return baseAssets The equivalent amount in base units.
     */
    function convertAssetToBase(address asset_, uint256 assets) public view returns (uint256 baseAssets) {
        if (asset_ == address(0)) revert IVault.ZeroAddress();
        uint256 rate = IProvider(getVaultStorage().provider).getRate(asset_);
        baseAssets = assets.mulDiv(rate, 10 ** (getAssetStorage().assets[asset_].decimals), Math.Rounding.Floor);
    }

    /**
     * @notice Converts a base amount to asset units.
     * @param asset_ The address of the asset.
     * @param baseAssets The amount of the assets in base units.
     * @return assets The equivalent amount in asset units.
     */
    function convertBaseToAsset(address asset_, uint256 baseAssets) public view returns (uint256 assets) {
        if (asset_ == address(0)) revert IVault.ZeroAddress();
        uint256 rate = IProvider(getVaultStorage().provider).getRate(asset_);
        assets = baseAssets.mulDiv(10 ** (getAssetStorage().assets[asset_].decimals), rate, Math.Rounding.Floor);
    }

    /**
     * @notice Adds a given amount of base assets to the total assets.
     * @param baseAssets The amount of base assets to add.
     */
    function addTotalAssets(uint256 baseAssets) public {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();
        if (!vaultStorage.alwaysComputeTotalAssets) {
            vaultStorage.totalAssets += baseAssets;
        }
    }

    /**
     * @notice Subtracts a given amount of base assets from the total assets.
     * @param baseAssets The amount of base assets to subtract.
     */
    function subTotalAssets(uint256 baseAssets) public {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();
        if (!vaultStorage.alwaysComputeTotalAssets) {
            vaultStorage.totalAssets -= baseAssets;
        }
    }

    /**
     * @notice Converts a given amount of shares to assets.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to convert.
     * @param rounding The rounding direction.
     * @return assets The amount of assets.
     * @return baseAssets The amount of base assets.
     */
    function convertToAssets(address asset_, uint256 shares, Math.Rounding rounding)
        public
        view
        returns (uint256 assets, uint256 baseAssets)
    {
        uint256 totalAssets = IVault(address(this)).totalAssets();
        uint256 totalSupply = getERC20Storage().totalSupply;
        baseAssets = shares.mulDiv(totalAssets + 1, totalSupply + 1, rounding);
        assets = convertBaseToAsset(asset_, baseAssets);
    }

    /**
     * @notice Converts a given amount of assets to shares.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction.
     * @return (shares, baseAssets) The equivalent amount of shares.
     */
    function convertToShares(address asset_, uint256 assets, Math.Rounding rounding)
        public
        view
        returns (uint256, uint256)
    {
        uint256 totalAssets = IVault(address(this)).totalAssets();
        uint256 totalSupply = getERC20Storage().totalSupply;
        uint256 baseAssets = convertAssetToBase(asset_, assets);
        uint256 shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
        return (shares, baseAssets);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function setProcessorRule(address target, bytes4 functionSig, IVault.FunctionRule calldata rule) public {
        getProcessorStorage().rules[target][functionSig] = rule;
        emit IVault.SetProcessorRule(target, functionSig, rule);
    }

    /**
     * @notice Sets the provider.
     * @param provider_ The address of the provider.
     */
    function setProvider(address provider_) public {
        if (provider_ == address(0)) {
            revert IVault.ZeroAddress();
        }
        getVaultStorage().provider = provider_;
        emit IVault.SetProvider(provider_);
    }

    /**
     * @notice Sets the buffer strategy.
     * @param buffer_ The address of the buffer strategy.
     */
    function setBuffer(address buffer_) public {
        if (buffer_ == address(0)) {
            revert IVault.ZeroAddress();
        }

        getVaultStorage().buffer = buffer_;
        emit IVault.SetBuffer(buffer_);
    }

    /**
     * @notice Computes the total assets in the vault.
     * @return totalBaseBalance The total base balance of the vault.
     */
    function computeTotalAssets() public view returns (uint256 totalBaseBalance) {
        IVault.VaultStorage storage vaultStorage = getVaultStorage();

        // Assumes native asset has same decimals as asset() (the base asset)
        totalBaseBalance = vaultStorage.countNativeAsset ? address(this).balance : 0;

        IVault.AssetStorage storage assetStorage = getAssetStorage();
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            uint256 balance = IERC20(assetList[i]).balanceOf(address(this));
            if (balance == 0) continue;
            totalBaseBalance += convertAssetToBase(assetList[i], balance);
        }
    }

    /**
     * @notice Processes a series of calls to target contracts.
     * @param targets The addresses of the target contracts.
     * @param values The values to send with the calls.
     * @param data The calldata for the calls.
     * @return returnData The return data from the calls.
     */
    function processor(address[] calldata targets, uint256[] memory values, bytes[] calldata data)
        public
        returns (bytes[] memory returnData)
    {
        uint256 targetsLength = targets.length;
        returnData = new bytes[](targetsLength);

        for (uint256 i = 0; i < targetsLength; i++) {
            Guard.validateCall(targets[i], values[i], data[i]);

            (bool success, bytes memory returnData_) = targets[i].call{value: values[i]}(data[i]);
            if (!success) {
                revert IVault.ProcessFailed(data[i], returnData_);
            }
            returnData[i] = returnData_;
        }
        emit IVault.ProcessSuccess(targets, values, returnData);
    }
}
