// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

interface IHooks {
    // @notice Config struct for the hooks
    // @dev Each flag is a boolean value that indicates if the corresponding function of hook has the permission to be called from vault
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

    function VAULT() external view returns (IVault);

    function setConfig(Config memory config_) external;
    function getConfig() external view returns (Config memory);

    function beforeDeposit(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external;
    function afterDeposit(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external;

    function beforeMint(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external;
    function afterMint(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external;

    function beforeRedeem(
        address asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external;
    function afterRedeem(address asset, uint256 shares, address caller, address receiver, address owner, uint256 assets)
        external;

    function beforeWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external;
    function afterWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external;

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external;
    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseBalanceAfterAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external;
}
