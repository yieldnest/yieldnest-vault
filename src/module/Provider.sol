// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    IProvider,
    IStETH,
    IMETH,
    IsfrxETH,
    IRETH,
    IswETH,
    IFrxEthWethDualOracle,
    IynLSDe
} from "src/interface/IProvider.sol";
import {IERC4626, ERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IWithdrawer} from "src/interface/IWithdrawer.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

/*
    The Provider fetches state from other contracts.
*/

contract Provider is IProvider {
    error UnsupportedAsset(address asset);

    function getRate(address asset) public view virtual returns (uint256) {
        if (asset == MC.WETH) {
            return 1e18;
        }

        if (asset == MC.STETH) {
            return 1e18;
        }

        if (asset == MC.OETH) {
            return 1e18;
        }

        if (asset == MC.BUFFER || asset == MC.YNETH || asset == MC.WOETH) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.YNLSDE) {
            // ynLSDe does not expose convertToAssets, use previewRedeem instead
            return IynLSDe(asset).previewRedeem(1e18);
        }

        if (asset == MC.WSTETH) {
            return IStETH(MC.STETH).getPooledEthByShares(1e18);
        }

        if (asset == MC.METH) {
            return IMETH(MC.METH_STAKING_MANAGER).mETHToETH(1e18);
        }

        if (asset == MC.RETH) {
            return IRETH(MC.RETH).getExchangeRate();
        }

        if (asset == MC.SWELL) {
            return IswETH(MC.SWELL).swETHToETHRate();
        }

        if (asset == MC.SFRXETH) {
            /* 
            
            The deposit asset for sfrxETH is frxETH and not ETH. In order to account for any frxETH/ETH rate fluctuations,
            an frxETH/ETH oracle is used as provided by Frax.

            Documentation: https://docs.frax.finance/frax-oracle/advanced-concepts
            */
            uint256 frxETHPriceInETH = IFrxEthWethDualOracle(MC.FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
            return IsfrxETH(MC.SFRXETH).pricePerShare() * frxETHPriceInETH / 1e18;
        }

        revert UnsupportedAsset(asset);
    }

    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view returns (uint256 baseAssets) {
        baseAssets = _asyncWithdrawalBalance(asset_);
    }

    function _asyncWithdrawalBalanceYNAsset(address queueManager_, address asset_)
        private
        view
        returns (uint256 baseAssets)
    {
        IWithdrawalQueueManager queueManager = IWithdrawalQueueManager(queueManager_);
        (, IWithdrawalQueueManager.WithdrawalRequest[] memory requests) =
            queueManager.withdrawalRequestsForOwner(msg.sender);

        uint256 decimals = 10 ** ERC20(asset_).decimals();

        for (uint256 i = 0; i < requests.length; i++) {
            if (!requests[i].processed) {
                // NOTE: needs to be fixed - assumes no slashing for now, as in reality eigenlayer slashing is not active yet
                // get base amount
                uint256 baseAmount = requests[i].amount * requests[i].redemptionRateAtRequestTime / decimals;
                // get fee
                uint256 fee = baseAmount * requests[i].feeAtRequestTime / 1000000;
                // add base amount minus fee

                baseAssets += baseAmount - fee;
            }
        }
        return baseAssets;
    }

    function _asyncWithdrawalBalanceWSTETH() private view returns (uint256 baseAssets) {
        IWithdrawalQueue queue = IWithdrawalQueue(MC.WSTETH_WITHDRAWAL_QUEUE);
        uint256[] memory requestIds = queue.getWithdrawalRequests(msg.sender);
        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = queue.getWithdrawalStatus(requestIds);
        for (uint256 i = 0; i < statuses.length; i++) {
            baseAssets += statuses[i].amountOfStETH;
        }
    }

    function _asyncWithdrawalBalanceWOETH() private view returns (uint256 baseAssets) {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        uint256[] memory requestIds = IWithdrawer(msg.sender).getWOETHRequestIds();
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
}
