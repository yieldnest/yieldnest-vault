// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {AsyncWithdrawalLib} from "src/library/AsyncWithdrawalLib.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
import {IProvider} from "src/interface/IProvider.sol";

interface IWithdrawer {
    function asyncWithdrawalBalance(address asset) external view returns (uint256);

    function getWOETHRequestIds() external view returns (uint256[] memory);

    function requestWithdrawalWOETH(uint256 amount) external returns (uint256);

    function requestWithdrawalOETH(uint256 amount) external returns (uint256);

    function claimWithdrawalsWOETH(uint256[] calldata requestIds)
        external
        returns (uint256[] memory amounts, uint256 totalAmount);
}
