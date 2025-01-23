// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/yearn/BaseStrategy.sol";

contract YNETHxLPStrategy is BaseStrategy {
    
    constructor(address _lpToken, string memory _name) BaseStrategy(_lpToken, _name) {}

    function _deployFunds(uint256 _amount) internal override{
        // TODO: implement
    }
    function _freeFunds(uint256 _amount) internal override {
        // TODO: implement
    }
    function _harvestAndReport() internal override  returns (uint256 _totalAssets){
        // TODO: implement
    }


}
