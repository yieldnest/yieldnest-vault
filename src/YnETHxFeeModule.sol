// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {OwnableUpgradeable, IERC4626, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {YnETHx} from "src/YnETHx.sol";
import {IFeeModule} from "src/interface/IFeeModule.sol";

contract YnETHxFeeModule is OwnableUpgradeable, IFeeModule {
    // performance deniminated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    YnETHx public immutable YNETHX;
    uint256 public immutable YNETHX_DECIMALS;
    uint256 public maximumAccountedExchangeRate;

    event PerformanceFeeCharged(address indexed recipient, uint256 sharesMinted, uint256 performanceFeeAmount);

    constructor(address ynETHx_) {
        YNETHX = YnETHx(payable(ynETHx_));
        YNETHX_DECIMALS = ERC20(address(YNETHX)).decimals();
    }

    function initialize(address owner_, uint256 performanceFee_, address performanceFeeRecipient_)
        external
        initializer
    {
        __Ownable_init(owner_);
        if (performanceFee_ > 1 ether) revert InvalidPerformanceFee();
        performanceFee = performanceFee_;
        performanceFeeRecipient = performanceFeeRecipient_;
        maximumAccountedExchangeRate = IERC4626(address(YNETHX)).convertToAssets(1 ether);
    }

    function chargePerformanceFee() external {
        if (msg.sender != address(YNETHX)) revert CallerNotVault();

        uint256 exchangeRateBeforeFee = IERC4626(address(YNETHX)).convertToAssets(1 ether);

        if (exchangeRateBeforeFee > maximumAccountedExchangeRate) {
            uint256 totalSupplyBeforeFee = IERC4626(address(YNETHX)).totalSupply();
            uint256 yieldEarned =
                (exchangeRateBeforeFee - maximumAccountedExchangeRate) * totalSupplyBeforeFee / (10 ** YNETHX_DECIMALS);
            uint256 feesAccrued = (yieldEarned * performanceFee) / 1 ether;

            if (performanceFeeRecipient != address(0)) {
                uint256 sharesToMint = IERC4626(address(YNETHX)).previewDeposit(feesAccrued);
                YNETHX.mintPerformanceFeeShares(performanceFeeRecipient, sharesToMint);
                emit PerformanceFeeCharged(performanceFeeRecipient, sharesToMint, feesAccrued);
            }

            uint256 exchangeRateAfterFee = IERC4626(address(YNETHX)).convertToAssets(1 ether);
            if (exchangeRateAfterFee > maximumAccountedExchangeRate) {
                maximumAccountedExchangeRate = exchangeRateAfterFee;
            }
        }
    }

    function setPerformanceFee(uint256 performanceFee_) external onlyOwner {
        if (performanceFee_ > 1 ether) revert InvalidPerformanceFee();
        performanceFee = performanceFee_;
    }

    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external onlyOwner {
        performanceFeeRecipient = performanceFeeRecipient_;
    }
}
