// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {OwnableUpgradeable, IERC4626, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {Math} from "src/Common.sol";
import {Vault} from "src/Vault.sol";

/**
 * @title Hooks
 * @notice Hooks for the Vault
 * @dev This contract gets callback from the vault it's attached to
 */
contract Hooks is OwnableUpgradeable, IHooks {
    using Math for uint256;

    // performance denominated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    uint256 public constant FEE_DENOMINATOR = 1 ether;
    IVault public immutable VAULT;
    uint256 public immutable VAULT_DECIMALS;

    /**
     * @notice Constructor
     * @param vault_ The address of the Vault to which this hooks contract is attached
     */
    constructor(address vault_) {
        VAULT = IVault(payable(vault_));
        VAULT_DECIMALS = ERC20(address(VAULT)).decimals();
    }

    /**
     * @notice Initialize the Hooks contract
     * @param owner_ The address of the owner of the contract
     * @param performanceFee_ The performance fee to be charged(denominated in 1e18)
     * @param performanceFeeRecipient_ The address of the performance fee recipient
     */
    function initialize(address owner_, uint256 performanceFee_, address performanceFeeRecipient_)
        external
        initializer
    {
        __Ownable_init(owner_);
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        if (performanceFeeRecipient_ == address(0)) revert InvalidPerformanceFeeRecipient();
        performanceFee = performanceFee_;
        performanceFeeRecipient = performanceFeeRecipient_;
    }

    /**
     * @notice Modifier to ensure that the caller is the Vault
     */
    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    /**
     * @notice Callback from the Vault after processing accounting
     * @dev This function is called after the Vault has processedAccounting done and mint shares equivalent to performance fee on yield generated
     * @param totalAssetsBefore The total assets before processing accounting
     * @param totalAssetsAfter The total assets after processing accounting
     * @param totalShares The total shares before processing accounting
     */
    function afterProcessAccounting(uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 totalShares)
        external
        onlyVault
    {
        if (totalAssetsAfter > totalAssetsBefore) {
            uint256 yieldEarned = totalAssetsAfter - totalAssetsBefore;
            uint256 feesAccrued = (yieldEarned * performanceFee) / FEE_DENOMINATOR;

            if (feesAccrued > 0) {
                uint256 sharesToMint =
                    feesAccrued.mulDiv(totalShares, totalAssetsAfter - feesAccrued, Math.Rounding.Floor);
                if (sharesToMint > 0) {
                    VAULT.mintShares(performanceFeeRecipient, sharesToMint);
                    emit PerformanceFeeCharged(
                        performanceFeeRecipient,
                        sharesToMint,
                        feesAccrued,
                        totalAssetsBefore,
                        totalAssetsAfter,
                        totalShares
                    );
                }
            }
        }
    }

    /**
     * @notice Callback from the Vault before withdraw
     * @param assets The amount of assets to be withdrawn
     * @param user The address of the user withdrawing
     */
    function beforeWithdraw(uint256 assets, address user) external onlyVault {
        Vault vault_ = Vault(payable(address(VAULT)));
        if (vault_.withdrawalFeeExempted(user)) return;
        uint256 fees = vault_._feeOnRaw(assets);
        uint256 sharesToMint = vault_.convertToShares(fees);
        if (sharesToMint > 0) {
            VAULT.mintShares(performanceFeeRecipient, sharesToMint);
            emit WithdrawFeeCharged(performanceFeeRecipient, sharesToMint, fees, assets);
        }
    }

    /**
     * @notice Callback from the Vault after redeem
     * @param shares The amount of shares to be redeemed
     * @param user The address of the user redeeming
     */
    function afterRedeem(uint256 shares, address user) external onlyVault {
        Vault vault_ = Vault(payable(address(VAULT)));
        if (vault_.withdrawalFeeExempted(user)) return;
        uint256 sharesToMint = vault_._feeOnTotal(shares);
        if (sharesToMint > 0) {
            VAULT.mintShares(performanceFeeRecipient, sharesToMint);
            emit RedeemFeeCharged(performanceFeeRecipient, sharesToMint, shares);
        }
    }

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
}
