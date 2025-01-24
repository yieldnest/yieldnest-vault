// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

interface ICurveLpConnector {
    function initialize(address admin) external;
    function rate() external view returns (int256, uint256);

    function deposit(uint256 _amountA, uint256 _amountB, uint256 _minOut) external returns (uint256);

    function withdraw(uint256 _amount, uint256 _minAmountA, uint256 _minAmountB) external returns (uint256[2] memory);
    function sweep(address _token, address _to) external;
}
