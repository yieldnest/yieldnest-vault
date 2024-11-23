// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MockBuffer} from "test/mainnet/mocks/MockBuffer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";

import {Test} from "lib/forge-std/src/Test.sol";

contract Etches is Test, MainnetActors {
    function mockAll() public {
        mockProvider();
        mockBuffer();
    }

    function mockProvider() public {
        Provider provider = new Provider();
        bytes memory code = address(provider).code;
        vm.etch(MC.PROVIDER, code);
    }

    function mockBuffer() public {
        MockBuffer buffer = new MockBuffer();
        bytes memory code = address(buffer).code;
        vm.etch(MC.BUFFER, code);
    }
}
