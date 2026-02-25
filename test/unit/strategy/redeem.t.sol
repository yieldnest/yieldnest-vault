// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Math} from "src/Common.sol";
import {IERC20} from "src/Common.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {SetupStrategy} from "test/unit/helpers/SetupStrategy.sol";
import {IVault} from "src/interface/IVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IAccessControl} from "src/Common.sol";

contract StrategyRedeemUnitTest is Test, Etches, MainnetActors {
    using Math for uint256;

    MockStrategy public strategy;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupStrategy setupStrategy = new SetupStrategy();
        (strategy, weth) = setupStrategy.setup();

        vm.prank(ADMIN);
        strategy.setAlwaysComputeTotalAssets(false);

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve strategy to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(strategy), type(uint256).max);

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), true);
    }

    function test_Strategy_Redeem_OnlyAllocator() public {
        // Give Alice some shares
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        strategy.deposit(INITIAL_BALANCE, alice);
        vm.stopPrank();

        // Enable allocator restriction
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);

        // Alice is NOT allocator, should revert
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, strategy.ALLOCATOR_ROLE()
            )
        );
        strategy.redeem(INITIAL_BALANCE, alice, alice);
        vm.stopPrank();

        // Grant ALLOCATOR_ROLE to Alice
        vm.startPrank(ADMIN);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();

        // Now Alice, as allocator, can redeem
        vm.prank(alice);
        strategy.redeem(INITIAL_BALANCE, alice, alice);
    }

    function test_Strategy_RedeemAsset_OnlyAllocator() public {
        // Give Alice some shares in asset
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        strategy.depositAsset(address(weth), INITIAL_BALANCE, alice);
        vm.stopPrank();

        // Enable allocator restriction
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);

        // Alice is NOT allocator, should revert
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, strategy.ALLOCATOR_ROLE()
            )
        );
        strategy.redeemAsset(address(weth), INITIAL_BALANCE, alice, alice);
        vm.stopPrank();

        // Grant ALLOCATOR_ROLE to Alice
        vm.startPrank(ADMIN);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), alice);
        vm.stopPrank();

        // Now Alice, as allocator, can redeemAsset
        vm.startPrank(alice);
        strategy.redeemAsset(address(weth), INITIAL_BALANCE, alice, alice);
        vm.stopPrank();
    }
}
