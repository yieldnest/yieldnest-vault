// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

contract Withdrawer is BaseWithdrawer {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) external virtual initializer {
        _initialize(admin, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
    }

    function _initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_
    ) internal virtual {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals_;
        vaultStorage.countNativeAsset = countNativeAsset_;
        vaultStorage.alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual override returns (uint256 baseAssets) {
        baseAssets = _asyncWithdrawalBalance(asset_);
    }

    function _asyncWithdrawalBalanceYNAsset(address queueManager_, address asset_)
        private
        view
        returns (uint256 baseAssets)
    {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) =
            queueManager.withdrawalRequestsForOwner(address(this));

        uint256 decimals = 10 ** _getAssetStorage().assets[asset_].decimals;

        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].processed) {
                // NOTE: needs to be fixed - assumes no slashing for now,
                // as in reality eigenlayer slashing is not active yet
                uint256 baseAmount = requests[i].amount * requests[i].redemptionRateAtRequestTime / decimals;
                uint256 fee = baseAmount * requests[i].feeAtRequestTime / 1000000;
                baseAssets += baseAmount - fee;
            }
        }
        return baseAssets;
    }

    function _asyncWithdrawalBalanceWSTETH() private view returns (uint256 baseAssets) {
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
        uint256[] memory requestIds = queue.getWithdrawalRequests(address(this));
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(requestIds);
        for (uint256 i = 0; i < statuses.length; i++) {
            baseAssets += statuses[i].amountOfStETH;
        }
    }

    function _asyncWithdrawalBalanceWOETH() private view returns (uint256 baseAssets) {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        uint256[] memory requestIds = OriginWithdrawalLib.getWOETHRequestIds();
        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestId = requestIds[i];
            IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(requestId);
            baseAssets += request.amount;
        }
    }

    function _asyncWithdrawalBalance(address asset) private view returns (uint256 baseAssets) {
        if (asset == MC.WOETH) {
            return _asyncWithdrawalBalanceWOETH();
        }

        if (asset == MC.WSTETH) {
            return _asyncWithdrawalBalanceWSTETH();
        }

        if (asset == MC.YNETH) {
            return _asyncWithdrawalBalanceYNAsset(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, MC.YNETH);
        }

        if (asset == MC.YNLSDE) {
            return _asyncWithdrawalBalanceYNAsset(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, MC.YNLSDE);
        }

        return 0;
    }

    function getWOETHRequestIds() external view returns (uint256[] memory) {
        return OriginWithdrawalLib.getWOETHRequestIds();
    }

    function requestWithdrawalWOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256) {
        return OriginWithdrawalLib.requestWithdrawalWOETH(amount);
    }

    function requestWithdrawalOETH(uint256 amount) public onlyRole(PROCESSOR_ROLE) returns (uint256) {
        return OriginWithdrawalLib.requestWithdrawalOETH(amount);
    }

    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        return OriginWithdrawalLib.claimWithdrawalsWOETH(requestIds);
    }
}
