// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626, IERC20} from "src/Common.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

library OriginWithdrawalLib {
    /// Events

    // @notice Emitted when a withdrawal request is made
    event WithdrawalRequested(address indexed asset, uint256 amount, uint256 requestId);
    // @notice Emitted when withdrawals are claimed
    event WithdrawalsClaimed(address indexed asset, uint256 baseAmount, uint256[] requestIds);

    // @notice Error thrown when not enough balance to make a withdrawal request
    error NotEnoughBalance();

    // @notice Storage for the origin withdrawal library
    struct OriginWithdrawalStorage {
        uint256[] requestIds;
    }

    /**
     * @notice Returns the storage for the origin withdrawal library.
     * @return $ The storage.
     */
    function getOriginWithdrawalStorage() public pure returns (OriginWithdrawalStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.withdraw.origin")
            $.slot := 0xe2a81ee947465acc258f2d8abf3a3ffc476a722503128e612f329dc71323cbde
        }
    }

    /**
     * @notice Adds a requestId to the main array.
     * @param id The requestId to add.
     */
    function _addRequestId(uint256 id) private {
        getOriginWithdrawalStorage().requestIds.push(id);
    }

    /**
     * @notice Removes requestIds from the main array.
     * @param idsToRemove The requestIds to remove.
     */
    function _removeRequestIds(uint256[] calldata idsToRemove) private {
        for (uint256 i = 0; i < idsToRemove.length; i++) {
            _removeRequestId(idsToRemove[i]);
        }
    }

    /**
     * @notice Removes a requestId from the main array.
     * @param id The requestId to remove.
     */
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

    /**
     * @notice Returns the requestIds array.
     * @return requestIds The requestIds array.
     */
    function getWOETHRequestIds() external view returns (uint256[] memory requestIds) {
        requestIds = getOriginWithdrawalStorage().requestIds;
    }

    /**
     * @notice Requests a withdrawal of WOETH.
     * @return requestId the requestId of the WOETH withdrawal.
     * @dev WOETH is a wrapper around OETH. This function will first redeem WOETH for OETH, then request the OETH withdrawal.
     */
    function requestWithdrawalWOETH(uint256 amount) public returns (uint256 requestId) {
        IERC4626 woeth = IERC4626(MC.WOETH);
        if (woeth.balanceOf(address(this)) < amount) {
            revert NotEnoughBalance();
        }

        uint256 amountInOETH = woeth.redeem(amount, address(this), address(this));

        requestId = _requestWithdrawalOETH(amountInOETH);
        emit WithdrawalRequested(MC.WOETH, amount, requestId);
    }

    /**
     * @notice Requests a withdrawal of OETH.
     * @return requestId the requestId of the OETH withdrawal.
     */
    function requestWithdrawalOETH(uint256 amount) public returns (uint256 requestId) {
        requestId = _requestWithdrawalOETH(amount);
        emit WithdrawalRequested(MC.OETH, amount, requestId);
    }

    /**
     * @notice Requests a withdrawal of OETH.
     * @return requestId the requestId of the OETH withdrawal.
     */
    function _requestWithdrawalOETH(uint256 amount) private returns (uint256 requestId) {
        IERC20 oeth = IERC20(MC.OETH);
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);
        if (oeth.balanceOf(address(this)) < amount) {
            revert NotEnoughBalance();
        }

        oeth.approve(address(oethVault), amount);
        (requestId,) = oethVault.requestWithdrawal(amount);

        _addRequestId(requestId);
    }

    /**
     * @notice Claims WOETH withdrawals.
     * @param requestIds the requestIds of the WOETH withdrawals to claim.
     * @return amounts the amounts of WOETH claimed.
     * @return totalAmount the total amount of WOETH claimed.
     */
    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        public
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        (amounts, totalAmount) = oethVault.claimWithdrawals(requestIds);

        _removeRequestIds(requestIds);
        emit WithdrawalsClaimed(MC.WOETH, totalAmount, requestIds);
    }

    /**
     * @notice Returns the total amount of WOETH that are in queue for withdrawal.
     * @return baseAssets amount in base units.
     */
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
