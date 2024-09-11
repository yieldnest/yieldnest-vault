// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MockStakeManager} from "test/mocks/MockListaStakeManager.sol";
import "forge-std/Test.sol";


contract Etches is Test {

    function mockListaStakeManager() public {
        MockStakeManager stakeManager = new MockStakeManager();
        bytes memory code = address(stakeManager).code;
        vm.etch(0x1adB950d8bB3dA4bE104211D5AB038628e477fE6, code);
    }
}
