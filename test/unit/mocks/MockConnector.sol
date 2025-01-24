// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {ICurveLpConnector} from "src/interface/ICurveLpConnector.sol";

contract MockConnector is ICurveLpConnector {
    int256 public storedRate;
    uint256 public timestamp;

    function initialize(address admin) external {}

    function rate() external view returns (int256, uint256) {
        return (storedRate, timestamp);
    }

    function setTimeStamp(uint256 _timestamp) external {
        timestamp = _timestamp;
    }

    function setRate(int256 _rate) external {
        storedRate = _rate;
    }

    function deposit(uint256 _amountA, uint256 _amountB, uint256 _minOut) external returns (uint256) {
        //empty
        return 0;
    }

    function withdraw(uint256 _amount, uint256 _minAmountA, uint256 _minAmountB) external returns (uint256[2] memory) {
        //empty
        return [uint256(0), uint256(0)];
    }

    function sweep(address _token, address _to) external {
        // empty
    }
}
