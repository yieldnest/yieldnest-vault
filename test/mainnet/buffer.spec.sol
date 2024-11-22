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

    function testAllocateWETHToBuffer() public {

        uint256 amount = 2000 ether;

        address user = makeAddr("user");
        vm.deal(user, amount);

        // Give user WETH
        vm.startPrank(user);
        IWETH(WETH).deposit{value: amount}();
        uint256 wethBalance = IWETH(WETH).balanceOf(user);
        emit log_named_uint("WETH Balance", wethBalance);
        IWETH(WETH).approve(address(buffer), amount);
        
        // Deposit WETH to buffer
        buffer.deposit(amount, user);
        vm.stopPrank();
        
        // Assert user received buffer shares
        uint256 bufferShares = buffer.balanceOf(user);
        assertEq(bufferShares, amount, "User should receive equal buffer shares");

        // Assert buffer received stETH
        uint256 stEthBalance = ILido(STETH).balanceOf(address(buffer));
        assertApproxEqAbs(stEthBalance, amount, 2, "Buffer should hold stETH");

        // Assert buffer total assets matches deposit
        uint256 totalAssets = buffer.totalAssets();
        assertApproxEqAbs(totalAssets, amount, 2, "Buffer total assets should match deposit");

        // Withdraw half of the amount
        uint256 halfAmount = amount / 2;
        uint256 halfShares = bufferShares / 2;

        vm.startPrank(user);
        buffer.redeem(halfShares, user, user);
        vm.stopPrank();

        // Assert user received WETH back
        uint256 userWethBalance = IWETH(WETH).balanceOf(user);
        assertApproxEqRel(userWethBalance, halfAmount, 0.001e18, "User should receive half WETH back");

        // Assert buffer shares were burned
        uint256 remainingShares = buffer.balanceOf(user);
        assertEq(remainingShares, halfShares, "User should have half shares remaining");

        // Assert buffer stETH balance decreased
        uint256 remainingStEth = ILido(STETH).balanceOf(address(buffer));
        assertApproxEqAbs(remainingStEth, halfAmount, 2, "Buffer should have half stETH remaining");
    }
}