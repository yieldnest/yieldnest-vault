// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault,IVault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {StETHBuffer, IWETH, ILido } from "test/mainnet/mocks/StETHBuffer.sol";


contract StETHBufferTest is Test, MainnetActors {

    StETHBuffer public buffer;

    address constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        buffer = new StETHBuffer(STETH, WETH);
        buffer.initialize(CURVE_POOL);
    }

    function allocateWETHToBuffer(uint256 amount) public {
        address user = makeAddr("user");
        vm.deal(user, amount);

        // Give user WETH
        vm.startPrank(user);
        IWETH(WETH).deposit{value: amount}();
        IWETH(WETH).approve(address(buffer), amount);
        
        // Deposit WETH to buffer
        buffer.deposit(amount, user);
        vm.stopPrank();
        
    }
}