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

    /// @notice The performance fee rate denominated in ether (1e18 = 100%)
    uint256 public performanceFee;

    /// @notice The address that receives performance fees
    address public performanceFeeRecipient;

    /// @notice The denominator used for fee calculations (1 ether = 100%)
    uint256 public constant FEE_DENOMINATOR = 1 ether;

    /// @notice The vault contract that this hooks contract is attached to
    IVault public immutable VAULT;

    /// @notice The configuration struct containing hook permissions
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
     * @notice Returns the name of the hooks module
     * @return The name of the hooks module
     */
    function name() external pure virtual returns (string memory) {
        return "PerformanceFeeHooks";
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
     * @dev This hook is called after the totalBaseAssets is updated
     * @dev This hook is mints the shares corresponding to the performance fee to the performanceFeeRecipient
     * @dev Computations are done in the base asset for maximum precision
     * @param params The after process accounting parameters
     */
    function afterProcessAccounting(AfterProcessAccountingParams calldata params) external virtual onlyVault {
        if (VAULT.alwaysComputeTotalAssets()) {
            /**
             * FeeHooks MUST NOT be called when alwaysComputeTotalAssets is enabled.
             *
             * alwaysComputeTotalAssets = true
             *   => _getVaultStorage().totalAssets has a lagging *undefined* value.
             *   => params.totalBaseAssetsAfterAccounting - params.totalBaseAssetsBeforeAccounting is *undefined*.
             *   => This delta includes principal and would cause charging fees on principal.
             */
            revert AlwaysComputeTotalAssetsIsEnabled();
        }

        // if there is increase in total base assets, then there is yield earned
        if (params.totalBaseAssetsAfterAccounting > params.totalBaseAssetsBeforeAccounting) {
            // calculate the yield earned and fees accrued
            uint256 yieldEarnedInBaseAsset =
                params.totalBaseAssetsAfterAccounting - params.totalBaseAssetsBeforeAccounting;
            uint256 feesAccruedInBaseAsset = (yieldEarnedInBaseAsset * performanceFee) / FEE_DENOMINATOR;

            if (feesAccruedInBaseAsset > 0) {
                if (params.totalBaseAssetsAfterAccounting <= feesAccruedInBaseAsset) {
                    revert FeesGreaterOrEqualToTotalBaseAssets();
                }

                // totalBaseAssetsAfterAccounting already includes the fees accrued
                // Shares need to be calculated for the rate after fees are substracted.
                // Therefore, we apply the formula:
                // sharesToMint = (fees * currentShareSupply) / (currentTotalBaseAssets - fees)
                uint256 sharesToMint = feesAccruedInBaseAsset.mulDiv(
                    params.totalSupplyBeforeAccounting,
                    params.totalBaseAssetsAfterAccounting - feesAccruedInBaseAsset,
                    Math.Rounding.Floor
                );

                if (sharesToMint > 0) {
                    VAULT.mintShares(performanceFeeRecipient, sharesToMint);

                    emit PerformanceFeeCharged(
                        performanceFeeRecipient,
                        sharesToMint,
                        feesAccruedInBaseAsset,
                        params.totalBaseAssetsBeforeAccounting,
                        params.totalBaseAssetsAfterAccounting,
                        params.totalSupplyBeforeAccounting
                    );
                }
            }
        }
    }

    /**
     * @notice Before withdraw hook function
     * @dev This hook is called before the withdraw is processed
     * @dev This hook is called before the shares and assets are updated in the vault
     * @param params The withdraw parameters
     */
    function beforeWithdraw(WithdrawParams calldata params) external virtual onlyVault {}

    /**
     * @notice After redeem hook function
     * @dev This hook is called after the redeem is processed
     * @param params The redeem parameters
     */
    function afterRedeem(RedeemParams calldata params) external virtual onlyVault {}

    /**
     * @notice Before deposit hook function
     * @dev This hook is called before the deposit is processed
     * @param params The deposit parameters
     */
    function beforeDeposit(DepositParams calldata params) external virtual onlyVault {}

    /**
     * @notice After deposit hook function
     * @dev This hook is called after the deposit is processed
     * @param params The deposit parameters
     */
    function afterDeposit(DepositParams calldata params) external virtual onlyVault {}

    /**
     * @notice Before mint hook function
     * @dev This hook is called before the mint is processed
     * @param params The mint parameters
     */
    function beforeMint(MintParams calldata params) external virtual onlyVault {}

    /**
     * @notice After mint hook function
     * @dev This hook is called after the mint is processed
     * @param params The mint parameters
     */
    function afterMint(MintParams calldata params) external virtual onlyVault {}

    /**
     * @notice Before redeem hook function
     * @dev This hook is called before the redeem is processed
     * @param params The redeem parameters
     */
    function beforeRedeem(RedeemParams calldata params) external virtual onlyVault {}

    /**
     * @notice After withdraw hook function
     * @dev This hook is called after the withdraw is processed
     * @param params The withdraw parameters
     */
    function afterWithdraw(WithdrawParams calldata params) external virtual onlyVault {}

    /**
     * @notice Before process accounting hook function
     * @dev This hook is called before the accounting is processed
     * @param params The before process accounting parameters
     */
    function beforeProcessAccounting(BeforeProcessAccountingParams calldata params) external virtual onlyVault {}

    /**
     * @notice Set the performance fee for the vault gains
     * @param performanceFee_ The performance fee to be charged(denominated in 1e18)
     */
    function setPerformanceFee(uint256 performanceFee_) external virtual onlyOwner {
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        emit SetPerformanceFee(performanceFee, performanceFee_);
        performanceFee = performanceFee_;
    }

    /**
     * @notice Set the performance fee recipient for the vault gains
     * @param performanceFeeRecipient_ The address of the performance fee recipient
     */
    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external virtual onlyOwner {
        if (performanceFeeRecipient_ == address(0)) revert InvalidPerformanceFeeRecipient();
        emit SetPerformanceFeeRecipient(performanceFeeRecipient, performanceFeeRecipient_);
        performanceFeeRecipient = performanceFeeRecipient_;
    }

    /**
     * @notice Set the config
     * @param config_ The config struct
     */
    function setConfig(Config memory config_) external virtual onlyOwner {
        Config memory oldConfig = config;
        config = config_;
        emit SetConfig(oldConfig, config_);
    }

    /**
     * @notice Get the hooks config
     * @return The hooks config struct
     */
    function getConfig() external view virtual returns (Config memory) {
        return config;
    }
}
