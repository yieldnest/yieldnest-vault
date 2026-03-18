// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interface/IVault.sol";

interface IHooks {
    /**
     * @notice Parameters for deposit operations
     */
    struct DepositParams {
        address asset;
        uint256 assets;
        address caller;
        address receiver;
        uint256 shares;
        uint256 baseAssets;
    }

    /**
     * @notice Parameters for mint operations
     */
    struct MintParams {
        address asset;
        uint256 shares;
        address caller;
        address receiver;
        uint256 assets;
        uint256 baseAssets;
    }

    /**
     * @notice Parameters for redeem operations
     */
    struct RedeemParams {
        address asset;
        uint256 shares;
        address caller;
        address receiver;
        address owner;
        uint256 assets;
    }

    /**
     * @notice Parameters for withdraw operations
     */
    struct WithdrawParams {
        address asset;
        uint256 assets;
        address caller;
        address receiver;
        address owner;
        uint256 shares;
    }

    /**
     * @notice Parameters for before process accounting operations
     */
    struct BeforeProcessAccountingParams {
        uint256 totalAssetsBeforeAccounting;
        uint256 totalSupplyBeforeAccounting;
        uint256 totalBaseAssetsBeforeAccounting;
    }

    /**
     * @notice Parameters for after process accounting operations
     */
    struct AfterProcessAccountingParams {
        uint256 totalAssetsBeforeAccounting;
        uint256 totalAssetsAfterAccounting;
        uint256 totalSupplyBeforeAccounting;
        uint256 totalSupplyAfterAccounting;
        uint256 totalBaseAssetsBeforeAccounting;
        uint256 totalBaseAssetsAfterAccounting;
    }

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
     * @notice Returns the name of the hooks module
     * @return The name of the hooks module
     */
    function name() external view returns (string memory);

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
     * @param params The deposit parameters
     */
    function beforeDeposit(DepositParams memory params) external;

    /**
     * @notice Hook called after deposit is processed
     * @param params The deposit parameters
     */
    function afterDeposit(DepositParams memory params) external;

    /**
     * @notice Hook called before mint is processed
     * @param params The mint parameters
     */
    function beforeMint(MintParams memory params) external;

    /**
     * @notice Hook called after mint is processed
     * @param params The mint parameters
     */
    function afterMint(MintParams memory params) external;

    /**
     * @notice Hook called before redeem is processed
     * @param params The redeem parameters
     */
    function beforeRedeem(RedeemParams memory params) external;

    /**
     * @notice Hook called after redeem is processed
     * @param params The redeem parameters
     */
    function afterRedeem(RedeemParams memory params) external;

    /**
     * @notice Hook called before withdraw is processed
     * @param params The withdraw parameters
     */
    function beforeWithdraw(WithdrawParams memory params) external;

    /**
     * @notice Hook called after withdraw is processed
     * @param params The withdraw parameters
     */
    function afterWithdraw(WithdrawParams memory params) external;

    /**
     * @notice Hook called before process accounting is executed
     * @param params The before process accounting parameters
     */
    function beforeProcessAccounting(BeforeProcessAccountingParams memory params) external;

    /**
     * @notice Hook called after process accounting is executed
     * @param params The after process accounting parameters
     */
    function afterProcessAccounting(AfterProcessAccountingParams memory params) external;
}
