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

    error InvalidPerformanceFee();
    error InvalidPerformanceFeeRecipient();
    error CallerNotVault();

    event PerformanceFeeCharged(
        address indexed recipient,
        uint256 sharesMinted,
        uint256 performanceFeeAmount,
        uint256 totalBaseAssetsBefore,
        uint256 totalBaseAssetsAfter,
        uint256 totalShares
    );
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);
    event SetPerformanceFeeRecipient(address indexed oldRecipient, address indexed newRecipient);
    event WithdrawFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 fees, uint256 assets);
    event RedeemFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 shares);

    function performanceFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);
    function VAULT() external view returns (IVault);

    function setPerformanceFee(uint256 performanceFee_) external;
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external;
    function setConfig(Config memory config_) external;
    function getConfig() external view returns (Config memory);

    function beforeDeposit(uint256 assets, address caller, address receiver, uint256 shares, uint256 baseAssets)
        external;
    function afterDeposit(uint256 assets, address caller, address receiver, uint256 shares, uint256 baseAssets)
        external;

    function beforeMint(uint256 shares, address caller, address receiver, uint256 assets, uint256 baseAssets)
        external;
    function afterMint(uint256 shares, address caller, address receiver, uint256 assets, uint256 baseAssets) external;

    function beforeRedeem(uint256 shares, address caller, address receiver, address owner, uint256 assets) external;
    function afterRedeem(uint256 shares, address caller, address receiver, address owner, uint256 assets) external;

    function beforeWithdraw(uint256 assets, address caller, address receiver, address owner, uint256 shares) external;
    function afterWithdraw(uint256 assets, address caller, address receiver, address owner, uint256 shares) external;

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
