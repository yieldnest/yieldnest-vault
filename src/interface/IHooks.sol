// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

interface IHooks {
    /**
     * @notice Config struct for the hooks
     * @dev Each flag is a boolean value that indicates if the corresponding hook function is enabled for the vault
     * if the flag is true, the hook function must be called by the vault.
     * if the flag is false, the hook function is expected to be a no-op.
     */
    struct Config {
        bool beforeDeposit;
        bool afterDeposit;
        bool beforeMint;
        bool afterMint;
        bool beforeRedeem;
        bool afterRedeem;
        bool beforeWithdraw;
        bool afterWithdraw;
        bool beforeProcessAccounting;
        bool afterProcessAccounting;
    }

    error CallerNotVault();

    /**
     * @notice Returns the vault that the hooks are attached to
     * @return The vault contract interface
     */
    function VAULT() external view returns (IVault);

    /**
     * @notice Sets the hooks configuration
     * @param config_ The configuration struct containing hook permissions
     */
    function setConfig(Config memory config_) external;

    /**
     * @notice Gets the current hooks configuration
     * @return The configuration struct containing hook permissions
     */
    function getConfig() external view returns (Config memory);

    /**
     * @notice Hook called before deposit is processed
     * @param asset The address of the asset being deposited
     * @param assets The amount of assets being deposited
     * @param caller The address initiating the deposit
     * @param receiver The address receiving the shares
     * @param shares The amount of shares to be minted
     * @param baseAssets The amount of base assets
     */
    function beforeDeposit(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external;

    /**
     * @notice Hook called after deposit is processed
     * @param asset The address of the asset that was deposited
     * @param assets The amount of assets that were deposited
     * @param caller The address that initiated the deposit
     * @param receiver The address that received the shares
     * @param shares The amount of shares that were minted
     * @param baseAssets The amount of base assets
     */
    function afterDeposit(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external;

    /**
     * @notice Hook called before mint is processed
     * @param asset The address of the asset being used for minting
     * @param shares The amount of shares being minted
     * @param caller The address initiating the mint
     * @param receiver The address receiving the shares
     * @param assets The amount of assets required
     * @param baseAssets The amount of base assets
     */
    function beforeMint(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external;

    /**
     * @notice Hook called after mint is processed
     * @param asset The address of the asset that was used for minting
     * @param shares The amount of shares that were minted
     * @param caller The address that initiated the mint
     * @param receiver The address that received the shares
     * @param assets The amount of assets that were required
     * @param baseAssets The amount of base assets
     */
    function afterMint(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external;

    /**
     * @notice Hook called before redeem is processed
     * @param asset The address of the asset being redeemed
     * @param shares The amount of shares being redeemed
     * @param caller The address initiating the redeem
     * @param receiver The address receiving the assets
     * @param owner The address owning the shares
     * @param assets The amount of assets to be received
     */
    function beforeRedeem(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external;

    /**
     * @notice Hook called after redeem is processed
     * @param asset The address of the asset that was redeemed
     * @param shares The amount of shares that were redeemed
     * @param caller The address that initiated the redeem
     * @param receiver The address that received the assets
     * @param owner The address that owned the shares
     * @param assets The amount of assets that were received
     */
    function afterRedeem(address asset, uint256 shares, address caller, address receiver, address owner, uint256 assets)
        external;

    /**
     * @notice Hook called before withdraw is processed
     * @param asset The address of the asset being withdrawn
     * @param assets The amount of assets being withdrawn
     * @param caller The address initiating the withdraw
     * @param receiver The address receiving the assets
     * @param owner The address owning the shares
     * @param shares The amount of shares to be burned
     */
    function beforeWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external;

    /**
     * @notice Hook called after withdraw is processed
     * @param asset The address of the asset that was withdrawn
     * @param assets The amount of assets that were withdrawn
     * @param caller The address that initiated the withdraw
     * @param receiver The address that received the assets
     * @param owner The address that owned the shares
     * @param shares The amount of shares that were burned
     */
    function afterWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external;

    /**
     * @notice Hook called before process accounting is executed
     * @param totalAssetsBeforeAccounting The total assets before accounting
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalBaseAssetsBeforeAccounting The total base assets before accounting
     */
    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseAssetsBeforeAccounting
    ) external;

    /**
     * @notice Hook called after process accounting is executed
     * @param totalAssetsBeforeAccounting The total assets before accounting
     * @param totalAssetsAfterAccounting The total assets after accounting
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalSupplyAfterAccounting The total supply after accounting
     * @param totalBaseAssetsAfterAccounting The total base assets after accounting
     * @param totalBaseAssetsBeforeAccounting The total base assets before accounting
     */
    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseAssetsAfterAccounting,
        uint256 totalBaseAssetsBeforeAccounting
    ) external;
}
