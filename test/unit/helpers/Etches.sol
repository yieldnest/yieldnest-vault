// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {MockYNETH} from "test/unit/mocks/MockYNETH.sol";
import {MockCL_STETH} from "test/unit/mocks/MockCL_STETH.sol";
import {MockYNLSDE} from "test/unit/mocks/MockYNLSDE.sol";
import {ETHRates} from "src/module/ETHRates.sol";
import {MockBuffer} from "test/unit/mocks/MockBuffer.sol";

import "lib/forge-std/src/Test.sol";

contract Etches is Test, MainnetContracts {
    function mockAll() public {
        mockWETH9();
        mockStETH();
        mockYNETH();
        mockYNLSDE();
        mockRETH();
        mockMETH();
        mockOETH();
        mockCL_STETH();
        mockETHRates();
        mockBuffer();
    }

    function mockWETH9() public {
        WETH9 weth = new WETH9();
        bytes memory code = address(weth).code;
        vm.etch(WETH, code);
    }

    function mockStETH() public {
        MockSTETH steth = new MockSTETH();
        bytes memory code = address(steth).code;
        vm.etch(STETH, code);
    }

    function mockYNETH() public {
        MockYNETH yneth = new MockYNETH();
        bytes memory code = address(yneth).code;
        vm.etch(YNETH, code);
    }

    function mockYNLSDE() public {
        MockYNLSDE ynlsde = new MockYNLSDE();
        bytes memory code = address(ynlsde).code;
        vm.etch(YNLSDE, code);
    }

    function mockRETH() public {
        WETH9 reth = new WETH9();
        bytes memory code = address(reth).code;
        vm.etch(RETH, code);
    }

    function mockMETH() public {
        WETH9 meth = new WETH9();
        bytes memory code = address(meth).code;
        vm.etch(METH, code);
    }

    function mockOETH() public {
        WETH9 oeth = new WETH9();
        bytes memory code = address(oeth).code;
        vm.etch(OETH, code);
    }

    function mockCL_STETH() public {
        MockCL_STETH cl_steth = new MockCL_STETH();
        bytes memory code = address(cl_steth).code;
        vm.etch(CL_STETH_FEED, code);
    }

    function mockETHRates() public {
        ETHRates rateProvider = new ETHRates();
        bytes memory code = address(rateProvider).code;
        vm.etch(ETH_RATE_PROVIDER, code);
    }

    function mockBuffer() public {
        MockBuffer buffer = new MockBuffer();
        bytes memory code = address(buffer).code;
        vm.etch(BUFFER_STRATEGY, code);
    }
}