// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MockStakeManager} from "test/mocks/MockListaStakeManager.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";

import "forge-std/Test.sol";

contract Etches is Test, MainnetContracts {
    function mockAllAssets() public {
        mockWETH9();
        mockStETH();
    }

    function mockWETH9() public {
        WETH9 weth = new WETH9();
        bytes memory code = address(weth).code;
        vm.etch(WETH, code);
    }

    function mockStETH() public {
        MockStETH steth = new MockStETH();
        bytes memory code = address(steth).code;
        vm.etch(STETH, code);
    }
}
