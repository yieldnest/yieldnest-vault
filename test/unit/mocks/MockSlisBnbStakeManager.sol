/* solhint-disable no-empty-blocks */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";

contract MockSlisBnbStakeManager is ISlisBnbStakeManager {
    function convertSnBnbToBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function convertBnbToSnBnb(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function deposit() external payable {}

    function getUserWithdrawalRequests(address) external pure returns (WithdrawalRequest[] memory reqs) {}

    function requestWithdraw(uint256 _amountInSnBnb) external {}

    function claimWithdraw(uint256 _idx) external {}

    function getUserRequestStatus(address _user, uint256 _idx)
        external
        view
        returns (bool _isClaimable, uint256 _amount)
    {}

    function BOT() external view returns (bytes32 bot) {}

    function claimUndelegated(address _validator) external returns (uint256 _uuid, uint256 _amount) {}

    function whitelistValidator(address _address) external {}

    function unbondingBnb() external view returns (uint256 _amount) {}

    function undelegateFrom(address _operator, uint256 _amount) external returns (uint256 amount_) {}

    function getAmountToUndelegate() external view returns (uint256 amount_) {}

    function reserveAmount() external view returns (uint256 amount_) {}
}
