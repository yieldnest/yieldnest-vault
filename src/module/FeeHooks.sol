// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Ownable, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {Math} from "src/Common.sol";
import {Vault} from "src/Vault.sol";

/**
 * @title FeeHooks
 * @notice FeeHooks for the Vault
 * @dev This contract gets callback from the vault it's attached to
 */
contract FeeHooks is Ownable, IHooks, IFeeHooks {
    using Math for uint256;

    // performance denominated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    uint256 public constant FEE_DENOMINATOR = 1 ether;
    IVault public immutable VAULT;
    Config public config;

    /**
     * @notice Constructor
     * @param vault_ The address of the Vault to which this hooks contract is attached
     * @param owner_ The address of the owner of the contract
     * @param performanceFee_ The performance fee to be charged(denominated in 1e18)
     * @param performanceFeeRecipient_ The address of the performance fee recipient
     * @param config_ The hooks config struct
     */
    constructor(
        address vault_,
        address owner_,
        uint256 performanceFee_,
        address performanceFeeRecipient_,
        Config memory config_
    ) Ownable(owner_) {
        VAULT = IVault(payable(vault_));
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        if (performanceFeeRecipient_ == address(0)) revert InvalidPerformanceFeeRecipient();
        performanceFee = performanceFee_;
        performanceFeeRecipient = performanceFeeRecipient_;
        config = config_;
    }

    /**
     * @notice Modifier to ensure that the caller is the Vault
     */
    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    /**
     * @notice After process accounting hook function
     * @dev This hook is called after the totalBaseBalance is updated
     * @dev This hook is mints the shares corresponding to the performance fee to the performanceFeeRecipient
     * @param totalAssetsBeforeAccounting The total assets before accounting
     * @param totalAssetsAfterAccounting The total assets after accounting
     * @param totalSupplyBeforeAccounting The total supply before accounting
     */
    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256,
        /**
         * totalSupplyAfterAccounting*
         */
        uint256,
        /**
         * totalBaseBalanceAfterAccounting*
         */
        uint256
    )
        /**
         * totalBaseBalanceBeforeAccounting*
         */
        external
        onlyVault
    {
        // if there is increase in total assets, then there is yield earned
        if (totalAssetsAfterAccounting > totalAssetsBeforeAccounting) {
            // calculate the yield earned and fees accrued
            uint256 yieldEarned = totalAssetsAfterAccounting - totalAssetsBeforeAccounting;
            uint256 feesAccrued = (yieldEarned * performanceFee) / FEE_DENOMINATOR;

            if (feesAccrued > 0) {
                // totalAssetsAfterAccounting already includes the fees accrued
                uint256 sharesToMint = feesAccrued.mulDiv(
                    totalSupplyBeforeAccounting, totalAssetsAfterAccounting - feesAccrued, Math.Rounding.Floor
                );
                if (sharesToMint > 0) {
                    VAULT.mintShares(performanceFeeRecipient, sharesToMint);
                    emit PerformanceFeeCharged(
                        performanceFeeRecipient,
                        sharesToMint,
                        feesAccrued,
                        totalAssetsBeforeAccounting,
                        totalAssetsAfterAccounting,
                        totalSupplyBeforeAccounting
                    );
                }
            }
        }
    }

    /**
     * @notice Before withdraw hook function
     * @dev This hook is called before the withdraw is processed
     * @dev This hook is mints the shares corresponding to the withdrawal fee to the performanceFeeRecipient
     * @dev This hook is called before the shares and assets are updated in the vault
     * @param assets The amount of assets to withdraw
     * @param caller The address of the caller(withdrawer)
     */
    function beforeWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address,
        /**
         * receiver*
         */
        address,
        /**
         * owner*
         */
        uint256
    )
        /**
         * shares*
         */
        external
        onlyVault
    {
        // calculates the fee to be added on top of the assets to withdraw
        // NOTE: In withdraw, assets to withdraw is fixed. So, fees is taken on top of the assets to withdraw
        uint256 fees = VAULT._feeOnRaw(assets, caller);
        // converts the fees to equivalent amount of shares to mint to the performanceFeeRecipient
        // accounting is done before the withdraw is processed, so totalAssets is not updated yet
        uint256 sharesToMint = VAULT.previewDepositAsset(asset, fees);

        // Store sharesToMint in transient storage for use in afterWithdraw
        assembly {
            tstore(0x01, sharesToMint)
        }
    }

    /**
     * @notice After withdraw hook function
     * @dev This hook is called after the withdraw is processed
     */
    function afterWithdraw(
        address asset,
        uint256 assets,
        address caller,
        address,
        /**
         * receiver*
         */
        address,
        /**
         * owner*
         */
        uint256
    )
        /**
         * shares*
         */
        external
        onlyVault
    {
        // Load sharesToMint from transient storage
        uint256 sharesToMint;
        assembly {
            sharesToMint := tload(0x01)
        }

        if (sharesToMint > 0) {
            VAULT.mintShares(performanceFeeRecipient, sharesToMint);
            emit WithdrawFeeCharged(performanceFeeRecipient, sharesToMint, 0, assets);
        }
    }

    /**
     * @notice After redeem hook function
     * @dev This hook is called after the redeem is processed
     * @dev This hook is mints the shares corresponding to the withdraw fee to the performanceFeeRecipient
     * @param shares The amount of shares to redeem
     * @param caller The address of the caller(redeemer)
     */
    function afterRedeem(
        address, /*asset*/
        uint256 shares,
        address caller,
        address,
        /**
         * receiver*
         */
        address,
        /**
         * owner*
         */
        uint256
    )
        /**
         * assets*
         */
        external
        onlyVault
    {
        // calculates the fee included in the shares to redeem
        // NOTE: In redeem, shares to burn is fixed. So, fee taken from users is already included in the shares to burn
        // If the assets corresponding to shares to redeem is X and fees is F, then X includes F already
        // So, we calculate the shares corresponding to fees F
        uint256 sharesToMint = VAULT._feeOnTotal(shares, caller);
        if (sharesToMint > 0) {
            VAULT.mintShares(performanceFeeRecipient, sharesToMint);
            emit RedeemFeeCharged(performanceFeeRecipient, sharesToMint, shares);
        }
    }
    /**
     * @notice Before deposit hook function
     * @dev This hook is called before the deposit is processed
     */

    function beforeDeposit(
        address, /*asset*/
        uint256, /*assets*/
        address, /*caller*/
        address, /*receiver*/
        uint256, /*shares*/
        uint256 /*baseAssets*/
    ) external onlyVault {}

    /**
     * @notice After deposit hook function
     * @dev This hook is called after the deposit is processed
     */
    function afterDeposit(
        address, /*asset*/
        uint256, /*assets*/
        address, /*caller*/
        address, /*receiver*/
        uint256, /*shares*/
        uint256 /*baseAssets*/
    ) external onlyVault {}

    /**
     * @notice Before mint hook function
     * @dev This hook is called before the mint is processed
     */
    function beforeMint(
        address, /*asset*/
        uint256, /*shares*/
        address, /*caller*/
        address, /*receiver*/
        uint256, /*assets*/
        uint256 /*baseAssets*/
    ) external onlyVault {}

    /**
     * @notice After mint hook function
     * @dev This hook is called after the mint is processed
     */
    function afterMint(
        address, /*asset*/
        uint256, /*shares*/
        address, /*caller*/
        address, /*receiver*/
        uint256, /*assets*/
        uint256 /*baseAssets*/
    ) external onlyVault {}

    /**
     * @notice Before redeem hook function
     * @dev This hook is called before the redeem is processed
     */
    function beforeRedeem(
        address, /*asset*/
        uint256, /*shares*/
        address, /*caller*/
        address, /*receiver*/
        address, /*owner*/
        uint256 /*assets*/
    ) external onlyVault {}

    /**
     * @notice Before process accounting hook function
     * @dev This hook is called before the accounting is processed
     */
    function beforeProcessAccounting(
        uint256, /*totalAssetsBeforeAccounting*/
        uint256, /*totalSupplyBeforeAccounting*/
        uint256 /*totalBaseBalanceBeforeAccounting*/
    ) external onlyVault {}

    /**
     * @notice Set the performance fee
     * @param performanceFee_ The performance fee to be charged(denominated in 1e18)
     */
    function setPerformanceFee(uint256 performanceFee_) external onlyOwner {
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        emit SetPerformanceFee(performanceFee, performanceFee_);
        performanceFee = performanceFee_;
    }

    /**
     * @notice Set the performance fee recipient
     * @param performanceFeeRecipient_ The address of the performance fee recipient
     */
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external onlyOwner {
        if (performanceFeeRecipient_ == address(0)) revert InvalidPerformanceFeeRecipient();
        emit SetPerformanceFeeRecipient(performanceFeeRecipient, performanceFeeRecipient_);
        performanceFeeRecipient = performanceFeeRecipient_;
    }

    /**
     * @notice Set the config
     * @param config_ The config struct
     */
    function setConfig(Config memory config_) external onlyOwner {
        config = config_;
    }

    /**
     * @notice Get the hooks config
     * @return The hooks config struct
     */
    function getConfig() external view returns (Config memory) {
        return config;
    }
}
