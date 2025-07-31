// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {OwnableUpgradeable, IERC4626, ERC20} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract Hooks is OwnableUpgradeable, IHooks {
    // performance denominated in ether(i.e. 1e18 = 100%)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    uint256 public constant FEE_DENOMINATOR = 1 ether;
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
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        performanceFee = performanceFee_;
        performanceFeeRecipient = performanceFeeRecipient_;
    }

    function afterProcessAccounting(uint256 totalAssetsBefore, uint256 totalAssetsAfter) external {
        if (msg.sender != address(VAULT)) revert CallerNotVault();

        if (totalAssetsAfter > totalAssetsBefore) {
            uint256 yieldEarned = totalAssetsAfter - totalAssetsBefore;
            uint256 feesAccrued = (yieldEarned * performanceFee) / FEE_DENOMINATOR;

            if (feesAccrued > 0) {
                uint256 sharesToMint = VAULT.previewDeposit(feesAccrued);
                if (sharesToMint > 0) {
                    VAULT.mintShares(performanceFeeRecipient, sharesToMint);
                    emit PerformanceFeeCharged(
                        performanceFeeRecipient, sharesToMint, feesAccrued, totalAssetsBefore, totalAssetsAfter
                    );
                }
            }
        }
    }

    function setPerformanceFee(uint256 performanceFee_) external onlyOwner {
        if (performanceFee_ > FEE_DENOMINATOR) revert InvalidPerformanceFee();
        emit SetPerformanceFee(performanceFee, performanceFee_);
        performanceFee = performanceFee_;
    }

    function setPerformanceFeeRecipient(address performanceFeeRecipient_) external onlyOwner {
        emit SetPerformanceFeeRecipient(performanceFeeRecipient, performanceFeeRecipient_);
        performanceFeeRecipient = performanceFeeRecipient_;
    }
}
