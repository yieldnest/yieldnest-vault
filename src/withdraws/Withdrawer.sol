// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {SafeERC20} from "src/Common.sol";

abstract contract Withdrawer is BaseVault {
    using SafeERC20 for IERC20;

    /// @notice Role for allocator permissions
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    struct StrategyStorage {
        bool hasAllocators;
    }

    /**
     * @dev This contract acts as a base for withdrawal handling where assets need withdrawal requests
     *  function processor will allow execution of queueing and claiming.
     *  must be able to worth for ETH and BNB as well. for example here processor should be able to handle
     * slisBNB withdrawals.
     *
     */

    // TODO: consider making a hierarchy of BaseStrategy with the allocator stuff and no buffer
    // that is inherited by Withdrawer. Do we need a BaseWithdrawer? this code should work for ETH/BNB etc.

    // TODO: Override maxWithdraw to remove buffer check and add allocator check
    // TODO: Override maxRedeem to remove buffer check and add allocator check
    // TODO: Override deposit to add allocator check
    // TODO: Override mint to add allocator check
    // TODO: Override withdraw to remove buffer check (already has allocator check)
    // TODO: Override redeem to remove buffer check and add allocator check
    // TODO: Override previewWithdraw to remove buffer check
    // TODO: Override previewRedeem to remove buffer check
    // TODO: Add modifier onlyAllocator that checks hasAllocators and ALLOCATOR_ROLE
    // TODO: Add function to toggle hasAllocators flag (admin only)
    // TODO: Add function to check if address is allocator

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        onlyAllocator
    {
        VaultStorage storage vaultStorage = _getVaultStorage();
        _subTotalAssets(assets);
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        // Transfer assets directly from vault to receiver
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _computeTotalAssets() internal view virtual override returns (uint256 totalBaseBalance) {
        // Get base balance from parent contract
        totalBaseBalance = super._computeTotalAssets();

        // Get storage
        AssetStorage storage assetStorage = _getAssetStorage();

        // Iterate through assets
        address[] memory assetList = assetStorage.list;
        uint256 assetListLength = assetList.length;

        for (uint256 i = 0; i < assetListLength; i++) {
            address asset_ = assetList[i];

            // Special handling for slisBNB
            if (asset_ == MainnetContracts.SLISBNB) {
                // Get total value of pending withdrawals from stake manager
                ISlisBnbStakeManager.WithdrawalRequest[] memory requests = ISlisBnbStakeManager(
                    MainnetContracts.SLIS_BNB_STAKE_MANAGER
                ).getUserWithdrawalRequests(address(this));
                uint256 withdrawalValue;
                for (uint256 j; j < requests.length; j++) {
                    withdrawalValue += requests[j].amountInSnBnb;
                }
                totalBaseBalance +=
                    ISlisBnbStakeManager(MainnetContracts.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(withdrawalValue);
            }
        }
    }

    // TODO: fix the naming here so it doesn't collide with kernelstrategy

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getStrategyStorage() internal pure virtual returns (StrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy")
            $.slot := 0x0ef3e973c65e9ac117f6f10039e07687b1619898ed66fe088b0fab5f5dc83d88
        }
    }

    /**
     * @notice Modifier to restrict access to allocator roles.
     */
    modifier onlyAllocator() {
        if (_getStrategyStorage().hasAllocators && !hasRole(ALLOCATOR_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, ALLOCATOR_ROLE);
        }
        _;
    }
}
