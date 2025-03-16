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

contract StrategyViewsUnitTest is Test, Etches, MainnetActors {
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

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(strategy), type(uint256).max);
    }

    function test_Strategy_GetHasAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        assertEq(strategy.getHasAllocator(), true, "Mock strategy should have allocators");
    }

    function test_Strategy_GetAssetWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(MC.WETH, true);
        assertEq(strategy.getAssetWithdrawable(MC.WETH), true, "Mock strategy should have WETH withdrawable");
    }

    function test_Strategy_MaxRedeem() public {
        assertEq(strategy.maxRedeem(address(alice)), 0, "Alice should have max redeem of 0");
        assertEq(strategy.maxRedeemAsset(MC.WETH, address(alice)), 0, "Alice should have max redeem of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxRedeem(address(alice)), INITIAL_BALANCE, "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxRedeemAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
    }

    function test_Stategy_MaxRedeem_Paused() public {
        assertEq(strategy.maxRedeem(address(alice)), 0, "Alice should have max redeem of 0");
        assertEq(strategy.maxRedeemAsset(MC.WETH, address(alice)), 0, "Alice should have max redeem of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxRedeem(address(alice)), INITIAL_BALANCE, "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxRedeemAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
        vm.prank(PAUSER);
        strategy.pause();
        assertEq(strategy.maxRedeem(address(alice)), 0, "Paused should have max redeem of 0");
        assertEq(strategy.maxRedeemAsset(MC.WETH, address(alice)), 0, "Paused should have max redeem of 0");
    }

    function test_Stategy_MaxRedeem_NotWithdrawable() public {
        assertEq(strategy.maxRedeem(address(alice)), 0, "Alice should have max redeem of 0");
        assertEq(strategy.maxRedeemAsset(MC.WETH, address(alice)), 0, "Alice should have max redeem of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxRedeem(address(alice)), INITIAL_BALANCE, "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxRedeemAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(MC.WETH, false);
        assertEq(strategy.maxRedeem(address(alice)), 0, "Max redeem should be 0 when withdrawable false");
        assertEq(strategy.maxRedeemAsset(MC.WETH, address(alice)), 0, "Paused should have max redeem of 0");
    }

    function test_Strategy_MaxWithdraw() public {
        assertEq(strategy.maxWithdraw(address(alice)), 0, "Alice should have max withdraw of 0");
        assertEq(strategy.maxWithdrawAsset(MC.WETH, address(alice)), 0, "Alice should have max withdraw of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxWithdraw(address(alice)), INITIAL_BALANCE, "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxWithdrawAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
    }

    function test_Stategy_MaxWithdraw_Paused() public {
        assertEq(strategy.maxWithdraw(address(alice)), 0, "Alice should have max withdraw of 0");
        assertEq(strategy.maxWithdrawAsset(MC.WETH, address(alice)), 0, "Alice should have max withdraw of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxWithdraw(address(alice)), INITIAL_BALANCE, "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxWithdrawAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
        vm.prank(PAUSER);
        strategy.pause();
        assertEq(strategy.maxWithdraw(address(alice)), 0, "Paused should have max withdraw of 0");
        assertEq(strategy.maxWithdrawAsset(MC.WETH, address(alice)), 0, "Paused should have max withdraw of 0");
    }

    function test_Stategy_MaxWithdraw_NotWithdrawable() public {
        assertEq(strategy.maxWithdraw(address(alice)), 0, "Alice should have max withdraw of 0");
        assertEq(strategy.maxWithdrawAsset(MC.WETH, address(alice)), 0, "Alice should have max withdraw of 0");
        vm.prank(alice);
        strategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            strategy.maxWithdraw(address(alice)), INITIAL_BALANCE, "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
        assertEq(
            strategy.maxWithdrawAsset(MC.WETH, address(alice)),
            INITIAL_BALANCE,
            "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(MC.WETH, false);
        assertEq(strategy.maxWithdraw(address(alice)), 0, "Max withdraw should be 0 when withdrawable false");
        assertEq(strategy.maxWithdrawAsset(MC.WETH, address(alice)), 0, "Paused should have max withdraw of 0");
    }

    function test_Strategy_PreviewMintAsset() public view {
        assertEq(
            strategy.previewMintAsset(address(weth), INITIAL_BALANCE),
            INITIAL_BALANCE,
            "Alice should have preview mint of INITIAL_BALANCE WETH"
        );
    }
}
