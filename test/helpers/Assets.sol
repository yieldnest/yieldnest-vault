// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "src/Common.sol";
import {IWETH} from "src/interface/IWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";

import "forge-std/Test.sol";

contract AssetHelper is Test {
    function get_weth(address user, uint256 amount) public {
        IWETH weth = IWETH(payable(MainnetContracts.WETH));
        deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.approve(user, amount);
        weth.transfer(user, amount);
    }
}
