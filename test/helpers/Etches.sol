// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {WETH9} from "test/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract Etches is Test {
    function mockWETH9() public {
        WETH9 weth = new WETH9();
        bytes memory code = address(weth).code;
        vm.etch(MainnetContracts.WETH, code);
    }
}
