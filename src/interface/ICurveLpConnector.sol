// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "src/Common.sol";
import {IStrategy} from "src/interface/IStrategy.sol";

interface ICurveLpConnector {
    function ASSET_A() external view returns (IERC20);
    function ASSET_B() external view returns (IERC20);
    function STRATEGY() external view returns (IStrategy);
    function rate() external view returns (int256, uint256);
    function deposit(uint256 _amountA, uint256 _amountB, uint256 _minOut) external returns (uint256);
    function withdraw(uint256 _amount, uint256 _minAmountA, uint256 _minAmountB) external returns (uint256[2] memory);
}
