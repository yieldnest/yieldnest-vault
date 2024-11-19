// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MockBuffer} from "test/mainnet/mocks/MockBuffer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {ETHRates} from "src/module/ETHRates.sol";
import {IERC20,TransparentUpgradeableProxy as TUP} from "src/Common.sol";

import {Test} from "lib/forge-std/src/Test.sol";

contract Etches is Test, MainnetActors {
    function mockAll() public {
        mockETHRates();
        mockBuffer();
    }

    function mockETHRates() public {
        ETHRates rateProvider = new ETHRates();
        bytes memory code = address(rateProvider).code;
        vm.etch(MC.ETH_RATE_PROVIDER, code);
    }

    function mockBuffer() public {
        MockBuffer buffer = new MockBuffer();
        bytes memory code = address(buffer).code;
        vm.etch(MC.BUFFER_STRATEGY, code);
    }
}
