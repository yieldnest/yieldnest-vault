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
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {MockNoOpHooks} from "test/unit/mocks/MockNoOpHooks.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TestHelpers} from "test/unit/helpers/TestHelpers.sol";
import {Vault} from "src/Vault.sol";

contract StrategyHooksUnitTest is Test, Etches, MainnetActors {
    using Math for uint256;

    MockStrategy public strategy;
    WETH9 public weth;
    IHooks public hooks;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;
    address public caller = address(0x2);

    function setUp() public {
        SetupStrategy setupStrategy = new SetupStrategy();
        (strategy, weth) = setupStrategy.setup();

        vm.prank(ADMIN);
        strategy.setAlwaysComputeTotalAssets(false);

        hooks = MockNoOpHooks(address(strategy.hooks()));

        vm.prank(ADMIN);
        strategy.setHooks(address(hooks));

        // Give Alice some tokens
        deal(caller, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(caller, INITIAL_BALANCE);

        // Approve strategy to spend Alice's tokens
        vm.prank(caller);
        weth.approve(address(strategy), type(uint256).max);

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), true);
    }

    function test_HooksFunction_OnlyCallableByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeDeposit(address(weth), 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterDeposit(address(weth), 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeMint(address(weth), 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterMint(address(weth), 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeRedeem(address(weth), 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterRedeem(address(weth), 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeWithdraw(address(weth), 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterWithdraw(address(weth), 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeProcessAccounting(1 ether, 1 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(1 ether, 1 ether, 1 ether, 0, 0, 0);
        vm.stopPrank();

        vm.startPrank(address(strategy));
        hooks.beforeDeposit(address(weth), 1 ether, alice, alice, 0, 0);
        hooks.afterDeposit(address(weth), 1 ether, alice, alice, 0, 0);
        hooks.beforeMint(address(weth), 1 ether, alice, alice, 0, 0);
        hooks.afterMint(address(weth), 1 ether, alice, alice, 0, 0);
        hooks.beforeRedeem(address(weth), 1 ether, alice, alice, alice, 0);
        hooks.afterRedeem(address(weth), 1 ether, alice, alice, alice, 0);
        hooks.beforeWithdraw(address(weth), 1 ether, alice, alice, alice, 0);
        hooks.afterWithdraw(address(weth), 1 ether, alice, alice, alice, 0);
        hooks.beforeProcessAccounting(1 ether, 1 ether, 1 ether);
        hooks.afterProcessAccounting(1 ether, 1 ether, 1 ether, 0, 0, 0);
        vm.stopPrank();
    }

    function test_depositHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeDeposit and afterDeposit to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeDeposit, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterDeposit, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            1
        );
        strategy.deposit(1 ether, alice);
        vm.stopPrank();
    }

    function test_depositHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeDeposit and afterDeposit to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeDeposit, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterDeposit, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            0
        );
        strategy.deposit(1 ether, alice);
        vm.stopPrank();
    }

    function test_depositAssetHooks_Enabled(uint8 assetIndex) public {
        address[] memory activeAssets = TestHelpers.getActiveAssets(IVault(address(strategy)));
        vm.assume(activeAssets.length > 0);
        vm.assume(assetIndex < activeAssets.length);

        // Use the asset at the given index
        address asset = activeAssets[assetIndex];

        // Setup caller with the selected asset
        if (asset == MC.WETH) {
            // Already set up in setUp()
        } else {
            // Deal tokens for other assets
            deal(asset, caller, INITIAL_BALANCE);
        }

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        uint256 depositAmount = 1 ether;
        uint256 sharesAmount = strategy.previewDepositAsset(asset, depositAmount);
        uint256 baseAssetAmount = strategy.convertToAssets(sharesAmount);

        vm.startPrank(caller);
        // Approve the strategy to spend the asset
        IERC20(asset).approve(address(strategy), 1 ether);
        // expect beforeDeposit and afterDeposit to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeDeposit, (asset, depositAmount, caller, alice, sharesAmount, baseAssetAmount)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterDeposit, (asset, depositAmount, caller, alice, sharesAmount, baseAssetAmount)),
            1
        );
        strategy.depositAsset(asset, depositAmount, alice);
        vm.stopPrank();
    }

    function test_mintHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: true,
                afterMint: true,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeMint and afterMint to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeMint, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterMint, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            1
        );
        strategy.mint(1 ether, alice);
        vm.stopPrank();
    }

    function test_mintHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeMint and afterMint to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeMint, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterMint, (address(weth), 1 ether, caller, alice, 1 ether, 1 ether)),
            0
        );
        strategy.mint(1 ether, alice);
        vm.stopPrank();
    }

    function test_redeemHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: true,
                afterRedeem: true,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.prank(caller);
        uint256 depositShares = strategy.deposit(1 ether, alice);

        // allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        uint256 assetsToRedeem = strategy.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeRedeem, (address(weth), sharesToRedeem, alice, alice, alice, assetsToRedeem)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterRedeem, (address(weth), sharesToRedeem, alice, alice, alice, assetsToRedeem)),
            1
        );
        strategy.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();
    }

    function test_redeemHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.prank(caller);
        uint256 depositShares = strategy.deposit(1 ether, alice);

        // allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        strategy.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeRedeem, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterRedeem, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            0
        );
        strategy.redeem(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: true,
                afterWithdraw: true,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        uint256 depositShares = strategy.deposit(1 ether, alice);
        vm.stopPrank();

        // allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        strategy.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeWithdraw, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterWithdraw, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            1
        );
        strategy.withdraw(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        uint256 depositShares = strategy.deposit(1 ether, alice);
        vm.stopPrank();

        // allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        strategy.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeWithdraw, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterWithdraw, (address(weth), 1 ether, alice, alice, alice, 1 ether)),
            0
        );
        strategy.withdraw(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawAssetHooks_Enabled(uint8 assetIndex) public {
        address[] memory activeAssets = TestHelpers.getActiveAssets(IVault(address(strategy)));
        vm.assume(activeAssets.length > 0);
        vm.assume(assetIndex < activeAssets.length);

        // Use the asset at the given index
        address asset = activeAssets[assetIndex];

        // Setup caller with the selected asset
        if (asset == MC.WETH) {
            // Already set up in setUp()
        } else {
            // Deal tokens for other assets
            deal(asset, caller, INITIAL_BALANCE);
        }

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: true,
                afterWithdraw: true,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        uint256 depositAmount = 1 ether;

        vm.startPrank(caller);
        IERC20(asset).approve(address(strategy), type(uint256).max);
        strategy.depositAsset(asset, depositAmount, alice);
        vm.stopPrank();

        // allocateToBuffer(1 ether);

        uint256 sharesToBurn = strategy.previewWithdrawAsset(asset, depositAmount);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeWithdraw, (asset, depositAmount, alice, alice, alice, sharesToBurn)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterWithdraw, (asset, depositAmount, alice, alice, alice, sharesToBurn)),
            1
        );
        strategy.withdrawAsset(asset, depositAmount, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawAssetHooks_Disabled(uint8 assetIndex) public {
        address[] memory activeAssets = TestHelpers.getActiveAssets(IVault(address(strategy)));
        vm.assume(activeAssets.length > 0);
        vm.assume(assetIndex < activeAssets.length);

        // Use the asset at the given index
        address asset = activeAssets[assetIndex];

        // Setup caller with the selected asset
        if (asset == MC.WETH) {
            // Already set up in setUp()
        } else {
            // Deal tokens for other assets
            deal(asset, caller, INITIAL_BALANCE);
        }

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        uint256 depositAmount = 1 ether;

        vm.startPrank(caller);
        IERC20(asset).approve(address(strategy), type(uint256).max);
        strategy.depositAsset(asset, depositAmount, alice);
        vm.stopPrank();

        // allocateToBuffer(1 ether);

        uint256 sharesToBurn = strategy.previewWithdrawAsset(asset, depositAmount);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeWithdraw, (asset, depositAmount, alice, alice, alice, sharesToBurn)),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterWithdraw, (asset, depositAmount, alice, alice, alice, sharesToBurn)),
            0
        );
        strategy.withdrawAsset(asset, depositAmount, alice, alice);
        vm.stopPrank();
    }

    function test_processAccountingHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: true,
                afterProcessAccounting: true
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        strategy.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to be called by 1 time
        vm.expectCall(address(hooks), abi.encodeCall(IHooks.beforeProcessAccounting, (1 ether, 1 ether, 1 ether)), 1);
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterProcessAccounting, (1 ether, 1 ether, 1 ether, 1 ether, 1 ether, 1 ether)),
            1
        );
        strategy.processAccounting();
        vm.stopPrank();
    }

    function test_processAccountingHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        strategy.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to not be called
        vm.expectCall(address(hooks), abi.encodeCall(IHooks.beforeProcessAccounting, (1 ether, 1 ether, 1 ether)), 0);
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterProcessAccounting, (1 ether, 1 ether, 1 ether, 1 ether, 1 ether, 1 ether)),
            0
        );
        strategy.processAccounting();
        vm.stopPrank();
    }

    function test_HooksAllSet() public {
        vm.prank(ADMIN);
        strategy.setHooks(address(hooks));

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: true,
                afterMint: true,
                beforeRedeem: true,
                afterRedeem: true,
                beforeWithdraw: true,
                afterWithdraw: true,
                beforeProcessAccounting: true,
                afterProcessAccounting: true
            })
        );
        vm.stopPrank();

        // expect all of the hooks to be called
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeDeposit.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterDeposit.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeMint.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterMint.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeRedeem.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterRedeem.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeWithdraw.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterWithdraw.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeProcessAccounting.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterProcessAccounting.selector), 1);

        vm.startPrank(caller);
        strategy.deposit(1 ether, alice);
        strategy.mint(1 ether, alice);
        vm.stopPrank();
        // allocateToBuffer(1 ether);

        strategy.processAccounting();

        vm.startPrank(alice);
        strategy.redeem(1 wei, alice, alice);
        strategy.withdraw(1 wei, alice, alice);
        vm.stopPrank();
    }

    function test_HooksNotSet() public {
        vm.prank(ADMIN);
        strategy.setHooks(address(0));

        // expect none of the hooks to not be called
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeDeposit.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterDeposit.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeMint.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterMint.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeRedeem.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterRedeem.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeWithdraw.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterWithdraw.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeProcessAccounting.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterProcessAccounting.selector), 0);

        vm.startPrank(caller);
        strategy.deposit(1 ether, alice);
        strategy.mint(1 ether, alice);
        vm.stopPrank();
        // allocateToBuffer(1 ether);

        strategy.processAccounting();

        vm.startPrank(alice);
        strategy.redeem(1 wei, alice, alice);
        strategy.withdraw(1 wei, alice, alice);
        vm.stopPrank();
    }
}
