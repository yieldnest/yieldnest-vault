// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {OwnableUpgradeable, IERC4626, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract Hooks is OwnableUpgradeable, IHooks {
    // performance denominated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    IVault public immutable VAULT;
    uint256 public immutable VAULT_DECIMALS;

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
    }

    function afterProcessAccounting(
        uint256 totalBaseAssetsBefore,
        uint256 totalBaseAssetsAfter,
        uint256 totalSupplyBefore
    ) external {
        if (msg.sender != address(VAULT)) revert CallerNotVault();

        if (totalBaseAssetsAfter > totalBaseAssetsBefore) {
            uint256 yieldEarned = totalBaseAssetsAfter - totalBaseAssetsBefore;
            // dividing by 1 ether because performanceFee is denominated in ether(i.e. 1e18 = 100%)
            uint256 feesAccrued = (yieldEarned * performanceFee) / 1 ether;

            if (feesAccrued > 0) {
                uint256 sharesToMint = VAULT.previewDeposit(feesAccrued);
                if (sharesToMint > 0) {
                    VAULT.mintShares(performanceFeeRecipient, sharesToMint);
                    emit PerformanceFeeCharged(
                        performanceFeeRecipient,
                        sharesToMint,
                        feesAccrued,
                        totalBaseAssetsBefore,
                        totalBaseAssetsAfter,
                        totalSupplyBefore
                    );
                }
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
