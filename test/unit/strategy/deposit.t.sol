// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Math} from "src/Common.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {SetupStrategy} from "test/unit/helpers/SetupStrategy.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IAccessControl} from "src/Common.sol";

contract StrategyDepositUnitTest is Test, Etches, MainnetActors {
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

    function test_Strategy_DepositAsset_Revert_OnlyAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, strategy.ALLOCATOR_ROLE()
            )
        );
        strategy.depositAsset(address(weth), INITIAL_BALANCE, alice);
    }

    function test_Strategy_Deposit_Revert_OnlyAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, strategy.ALLOCATOR_ROLE()
            )
        );
        strategy.deposit(INITIAL_BALANCE, alice);
    }
}
