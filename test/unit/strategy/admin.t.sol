// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy, IAccessControl} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Math} from "src/Common.sol";
import {IERC20, IERC20Metadata} from "src/Common.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {MainnetActors} from "script/Actors.sol";
import {SetupStrategy} from "test/unit/helpers/SetupStrategy.sol";
import {MockERC20CustomDecimals as MockERC20} from "test/unit/mocks/MockERC20CustomDecimals.sol";
import {IVault} from "src/interface/IVault.sol";

contract StrategAdminUnitTest is Test, Etches, MainnetActors {
    using Math for uint256;

    MockStrategy public strategy;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    IERC20 public asset;

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

        asset = new MockERC20("Asset", "AST", 18);
    }

    function test_Strategy_setHasAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        assertEq(strategy.getHasAllocator(), true);

        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(false);
        assertEq(strategy.getHasAllocator(), false);
    }

    function test_Strategy_setHasAllocator_unauthorized() public {
        bytes memory error = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, strategy.ALLOCATOR_MANAGER_ROLE()
        );
        vm.expectRevert(error);
        vm.prank(UNAUTHORIZED);
        strategy.setHasAllocator(true);
    }

    function test_Strategy_setAssetWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset), true);

        assertEq(strategy.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(asset), true);

        assertEq(strategy.getAssetWithdrawable(address(asset)), true, "asset should be withdrawable");

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(asset), false);

        assertEq(strategy.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");
    }

    function test_Strategy_setAssetWithdrawable_assetNotAdded() public {
        assertEq(strategy.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(asset), true);

        assertEq(strategy.getAssetWithdrawable(address(asset)), true, "asset should be withdrawable");

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(asset), false);

        assertEq(strategy.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");
    }

    function test_Strategy_setAssetWithdrawable_unauthorized() public {
        bytes memory error = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, strategy.ASSET_MANAGER_ROLE()
        );
        vm.expectRevert(error);
        vm.prank(UNAUTHORIZED);
        strategy.setAssetWithdrawable(address(asset), true);
    }

    function test_Strategy_addAsset_Depositable_NotWithdrawable() public {
        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset2), 12, true, false);

        assertEq(strategy.getAsset(address(asset2)).active, true, "asset2 should be active");
        assertEq(strategy.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset2)), false, "asset2 should not be withdrawable");

        MockERC20 asset3 = new MockERC20("Mock Token 3", "MOCK3", 10);
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset3), true);

        assertEq(strategy.getAsset(address(asset3)).active, true, "asset2 should be active");
        assertEq(strategy.getAsset(address(asset3)).decimals, 10, "asset2 should have 10 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset3)), false, "asset2 should not be withdrawable");
    }

    function test_Strategy_addAsset_Depositable_Withdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset), true, true);

        assertEq(strategy.getAsset(address(asset)).active, true);
        assertEq(strategy.getAsset(address(asset)).decimals, 18, "asset should have 18 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset)), true, "asset should not be withdrawable");
    }

    function test_Strategy_addAsset_NotDepositable_NotWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset), false);
        assertEq(strategy.getAsset(address(asset)).active, false);
        assertEq(strategy.getAsset(address(asset)).decimals, 18, "asset should have 18 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");

        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset2), 12, false, false);

        assertEq(strategy.getAsset(address(asset2)).active, false, "asset2 should not be active");
        assertEq(strategy.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset2)), false, "asset2 should not be withdrawable");

        MockERC20 asset3 = new MockERC20("Mock Token 3", "MOCK3", 10);
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset3), false);

        assertEq(strategy.getAsset(address(asset3)).active, false, "asset2 should not be active");
        assertEq(strategy.getAsset(address(asset3)).decimals, 10, "asset2 should have 10 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset3)), false, "asset2 should not be withdrawable");
    }

    function test_Strategy_addAsset_NotDepositable_Withdrawable() public {
        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        strategy.addAsset(address(asset2), 12, false, true);

        assertEq(strategy.getAsset(address(asset2)).active, false, "asset2 should not be active");
        assertEq(strategy.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(strategy.getAssetWithdrawable(address(asset2)), true, "asset2 should be withdrawable");
    }

    function test_Strategy_addAsset_nullAddress() public {
        vm.prank(ASSET_MANAGER);
        // call reverts when trying to get decimals from zero address
        vm.expectRevert();
        strategy.addAsset(address(0), true);

        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        strategy.addAsset(address(0), 18, true, true);

        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        strategy.addAsset(address(0), true, true);
    }

    function test_Strategy_addAsset_duplicateAddress() public {
        vm.startPrank(ASSET_MANAGER);
        strategy.addAsset(address(asset), 18, true, true);

        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(asset)));
        strategy.addAsset(address(asset), 18, true, true);

        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(asset)));
        strategy.addAsset(address(asset), true, true);
    }

    function test_Strategy_addAsset_unauthorized() public {
        bytes memory error = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, UNAUTHORIZED, strategy.ASSET_MANAGER_ROLE()
        );
        vm.expectRevert(error);
        vm.prank(UNAUTHORIZED);
        strategy.addAsset(address(asset), true);

        vm.expectRevert(error);
        vm.prank(UNAUTHORIZED);
        strategy.addAsset(address(asset), 18, true, true);

        vm.expectRevert(error);
        vm.prank(UNAUTHORIZED);
        strategy.addAsset(address(asset), true, true);
    }

    function test_deleteAsset_Withdrawable() public {
        assertTrue(strategy.getAsset(address(MC.STETH)).active, "STETH should be active");
        assertTrue(strategy.getAssetWithdrawable(address(MC.STETH)), "STETH should be withdrawable");

        vm.startPrank(ASSET_MANAGER);
        strategy.deleteAsset(strategy.getAsset(address(MC.STETH)).index);
        vm.stopPrank();

        assertEq(strategy.getAsset(address(MC.STETH)).active, false, "STETH should not be active");
        assertEq(strategy.getAsset(address(MC.STETH)).index, 0, "STETH should have index 0");
        assertEq(strategy.getAsset(address(MC.STETH)).decimals, 0, "STETH should have 0 decimals after deletion");
        assertEq(strategy.getAssetWithdrawable(address(MC.STETH)), false, "STETH should not be withdrawable");
    }
}
