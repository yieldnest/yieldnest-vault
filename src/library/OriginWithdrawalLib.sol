// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626, IERC20} from "src/Common.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

library OriginWithdrawalLib {
    event WOETHWithdrawalRequested(uint256 assetAmount, uint256 requestId);
    event WOETHWithdrawalsClaimed(uint256 baseAmount, uint256[] requestIds);
    event OETHWithdrawalRequested(uint256 assetAmount, uint256 requestId);

    struct OriginWithdrawalStorage {
        uint256[] requestIds;
    }

    function getOriginWithdrawalStorage() public pure returns (OriginWithdrawalStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.withdraw.origin")
            $.slot := 0xe2a81ee947465acc258f2d8abf3a3ffc476a722503128e612f329dc71323cbde
        }
    }

    // Function to add a requestId to the main array
    function _addRequestId(uint256 id) private {
        getOriginWithdrawalStorage().requestIds.push(id);
    }

    // Function to remove an array of requestIds from the main array
    function _removeRequestIds(uint256[] calldata idsToRemove) private {
        for (uint256 i = 0; i < idsToRemove.length; i++) {
            _removeRequestId(idsToRemove[i]);
        }
    }

    // Internal function to remove a single requestId
    function _removeRequestId(uint256 id) private {
        uint256[] storage requestIds = getOriginWithdrawalStorage().requestIds;

        for (uint256 i = 0; i < requestIds.length; i++) {
            if (requestIds[i] == id) {
                requestIds[i] = requestIds[requestIds.length - 1]; // Move the last element to the current index
                requestIds.pop(); // Remove the last element
                break; // Exit the loop after removing the element
            }
        }
    }

    function getWOETHRequestIds() external view returns (uint256[] memory) {
        return getOriginWithdrawalStorage().requestIds;
    }

    function requestWithdrawalWOETH(uint256 amount) public returns (uint256 requestId) {
        IERC4626 woeth = IERC4626(MC.WOETH);
        IERC20 oeth = IERC20(MC.OETH);
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 amountInOETH = woeth.redeem(amount, address(this), address(this));
        oeth.approve(address(oethVault), amountInOETH);
        (requestId,) = oethVault.requestWithdrawal(amountInOETH);

        _addRequestId(requestId);

        emit WOETHWithdrawalRequested(amount, requestId);
    }

    function requestWithdrawalOETH(uint256 amount) public returns (uint256 requestId) {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        IERC20 oeth = IERC20(MC.OETH);

        oeth.approve(address(oethVault), amount);
        (requestId,) = oethVault.requestWithdrawal(amount);
        _addRequestId(requestId);
        emit OETHWithdrawalRequested(amount, requestId);
    }

    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        (amounts, totalAmount) = oethVault.claimWithdrawals(requestIds);

        _removeRequestIds(requestIds);
        emit WOETHWithdrawalsClaimed(totalAmount, requestIds);
    }

    function _asyncWithdrawalBalanceWOETH() internal view returns (uint256 baseAssets) {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256[] storage requestIds = getOriginWithdrawalStorage().requestIds;
        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestId = requestIds[i];
            IOETHVault.WithdrawalRequest memory request = oethVault.withdrawalRequests(requestId);
            baseAssets += request.amount;
        }
    }
}
