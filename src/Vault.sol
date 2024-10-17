// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Address,
    IERC20,
    IVault,
    SafeERC20,
    Storage,
    ERC20PermitUpgradeable
} from "./Common.sol";

contract Vault is IVault, Storage, ERC20PermitUpgradeable {
    
    using SafeERC20 for IERC20;
    using Address for address;

    function asset() public view virtual returns (address) {
        VaultStorage storage $ = _getVaultStorage();
        return $.baseAsset;
    }
    
    function assets() public view returns (address[] memory assets_) {
        AssetStorage storage $ = _getAssetStorage();
        uint256 assetListLength = $.assetList.length;
        assets_ = new address[](assetListLength);
        for (uint256 i = 0; i < assetListLength; i++) {
            assets_[i] = $.assetList[i];
        }
    }

    function decimals() public view virtual override(IERC20Metadata, ERC20Upgradeable) returns (uint8) {
        VaultStorage storage $ = Storage.getVaultStorage();
        return $.baseDecimals + _decimalsOffset();
    }

    function totalAssets() public view virtual returns (uint256) {
        AssetStorage storage $ = Storage.getVaultStorage();
        return $.totalAssets;
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        ERC20Storage storage $ = Storage._getERC20Storage();
        return $.balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewDepositAsset(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }    

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    function previewMintAsset(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev See {IAssetVault-depositAsset}. */
    function depositAsset(address asset, uint256 amount, address receiver) public virtual returns (uint256) {
        // uint256 maxAssets = maxDeposit(receiver);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        // }

        // uint256 shares = previewDeposit(assets);
        // _deposit(_msgSender(), receiver, assets, shares);

        // return shares;
    }    

    /** @dev See {IERC4626-mint}.
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

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        // uint256 maxAssets = maxWithdraw(owner);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        // }

        // uint256 shares = previewWithdraw(assets);
        // _withdraw(_msgSender(), receiver, owner, assets, shares);

        // return shares;
    }

    /** @dev See {IERC4626-redeem}. */
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
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(address asset, uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        
        uint256 convertedAssets = _convertToBasePrice(asset, assets);
        
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        // return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        // ERC4626Storage storage $ = _getERC4626Storage();
        // // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // // calls the vault, which is assumed not malicious.
        // //
        // // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // // assets are transferred and before the shares are minted, which is a valid state.
        // // slither-disable-next-line reentrancy-no-eth
        // SafeERC20.safeTransferFrom($._asset, caller, address(this), assets);
        // _mint(receiver, shares);

        // emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
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

    function _getStrategyWithLowestBalance() internal view returns (address strategyAddress, uint256 lowestBalance) {
        StrategyStorage storage $ = Storage.getStrategyStorage();
        uint256 lowestBalanceFound = type(uint256).max;
        address strategyWithLowestBalance;

        for (uint256 i = 0; i < $.strategyList.length; i++) {
            address strategy = $.strategyList[i];
            uint256 currentBalance = $.strategies[strategy].currentBalance;
            if (currentBalance < lowestBalanceFound) {
                lowestBalanceFound = currentBalance;
                strategyWithLowestBalance = strategy;
            }
        }

        return (strategyWithLowestBalance, lowestBalanceFound);
    }
  
    function processAccounting() public {
        // get the balances of the assets
        AssetStorage storage assetStorage = _getAssetStorage();
        
        for (uint256 i = 0; i < assetsStorage.list.length; i++) {
            address asset = assets[i];
            idleBalance = asset.balanceOf(address(vault));
        }
        // get the balances of the strategies

        // call convertToAssets on the strategie?



        // NOTE: Get the loops out of the public calls
    } 
}