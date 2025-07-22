// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {OwnableUpgradeable, IERC4626, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {YnETHx} from "src/YnETHx.sol";
import {IFeeModule} from "src/interface/IFeeModule.sol";

contract FeeModule is OwnableUpgradeable, IFeeModule {
    // performance denominated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    IVault public immutable VAULT;
    uint256 public immutable VAULT_DECIMALS;
    uint256 public maximumAccountedExchangeRate;

    constructor(address vault_) {
        VAULT = IVault(payable(vault_));
        VAULT_DECIMALS = ERC20(address(VAULT)).decimals();
    }

    function initialize(address owner_, uint256 performanceFee_, address performanceFeeRecipient_)
        external
        initializer
    {
        __Ownable_init(owner_);
        if (performanceFee_ > 1 ether) revert InvalidPerformanceFee();
        performanceFee = performanceFee_;
        performanceFeeRecipient = performanceFeeRecipient_;
        maximumAccountedExchangeRate = IERC4626(address(VAULT)).convertToAssets(10 ** VAULT_DECIMALS);
    }

    function chargePerformanceFee() external {
        if (msg.sender != address(VAULT)) revert CallerNotVault();

        uint256 exchangeRateBeforeFee = IERC4626(address(VAULT)).convertToAssets(10 ** VAULT_DECIMALS);

        if (exchangeRateBeforeFee > maximumAccountedExchangeRate) {
            uint256 totalSupplyBeforeFee = IERC4626(address(VAULT)).totalSupply();
            uint256 yieldEarned =
                (exchangeRateBeforeFee - maximumAccountedExchangeRate) * totalSupplyBeforeFee / (10 ** VAULT_DECIMALS);
            uint256 feesAccrued = (yieldEarned * performanceFee) / 1 ether;

            if (performanceFeeRecipient != address(0)) {
                uint256 sharesToMint = IERC4626(address(VAULT)).previewDeposit(feesAccrued);
                VAULT.mintPerformanceFeeShares(performanceFeeRecipient, sharesToMint);
                emit PerformanceFeeCharged(performanceFeeRecipient, sharesToMint, feesAccrued);
            }

            uint256 exchangeRateAfterFee = IERC4626(address(VAULT)).convertToAssets(10 ** VAULT_DECIMALS);
            if (exchangeRateAfterFee > maximumAccountedExchangeRate) {
                maximumAccountedExchangeRate = exchangeRateAfterFee;
            }
        }
    }

    function setPerformanceFee(uint256 performanceFee_) external onlyOwner {
        if (performanceFee_ > 1 ether) revert InvalidPerformanceFee();
        emit SetPerformanceFee(performanceFee, performanceFee_);
        performanceFee = performanceFee_;
    }

    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external onlyOwner {
        emit SetPerformanceFeeRecipient(performanceFeeRecipient, performanceFeeRecipient_);
        performanceFeeRecipient = performanceFeeRecipient_;
    }
}
