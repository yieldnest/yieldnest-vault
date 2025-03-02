// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Math} from "src/Common.sol";
import {IERC20, IERC20Metadata} from "src/Common.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {MainnetActors} from "script/Actors.sol";
import {SetupStrategy} from "test/unit/helpers/SetupStrategy.sol";

contract StrategAdminUnitTest is Test, Etches, MainnetActors {
    using Math for uint256;

    MockStrategy public strategy;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupStrategy setupStrategy = new SetupStrategy();
        (strategy, weth) = setupStrategy.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve strategy to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(strategy), type(uint256).max);
    }

    function test_Strategy_SetHasAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        assertEq(strategy.getHasAllocator(), true, "Mock strategy should have allocators");
    }

    function test_Strategy_SetHasAllocator_RevertUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        strategy.setHasAllocator(true);
    }

    function test_Strategy_AddAsset() public {
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(MC.METH, true, true);
        assertEq(strategy.getAssetWithdrawable(MC.METH), true, "METH should be withdrawable");
    }
}
