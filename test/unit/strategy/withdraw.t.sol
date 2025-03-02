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
import {FeeMath} from "src/module/FeeMath.sol";

contract StrategWithdrawUnitTest is Test, Etches, MainnetActors {
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

        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), true);
    }

    function test_Strategy_Withdraw_Revert_AssetNotWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), false);
        vm.prank(alice);
        vm.expectRevert();
        strategy.withdraw(INITIAL_BALANCE, alice, alice);
    }

    function test_Strategy_WithdrawAsset_Revert_AssetNotWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), false);
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        strategy.depositAsset(address(weth), INITIAL_BALANCE, alice);
        vm.expectRevert();
        strategy.withdrawAsset(address(weth), INITIAL_BALANCE, alice, alice);
        vm.stopPrank();
    }

    function test_Strategy_Deposit_Revert_OnlyAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        strategy.setHasAllocator(true);
        vm.startPrank(alice);
        weth.approve(address(strategy), INITIAL_BALANCE);
        vm.expectRevert();
        strategy.depositAsset(address(weth), INITIAL_BALANCE, alice);
    }

    function test_Strategy_WithdrawAsset(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.prank(alice);
        strategy.deposit(assets, alice);

        uint256 maxWithdraw = strategy.maxWithdrawAsset(address(weth), alice);
        uint256 previewRedeemAssets = strategy.previewRedeemAsset(address(weth), strategy.balanceOf(alice));

        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        uint256 expectedShares = strategy.previewDepositAsset(address(weth), maxWithdraw);

        // Verify we can actually withdraw the max amount
        vm.prank(alice);
        uint256 withdrawnShares = strategy.withdrawAsset(address(weth), maxWithdraw, alice, alice);

        assertApproxEqAbs(withdrawnShares, expectedShares, 5, "Withdrawn shares should match expected");
        assertApproxEqAbs(strategy.balanceOf(alice), 0, 5, "Alice should have no shares remaining");
    }

    function test_Strategy_RedeemAsset(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.prank(alice);
        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        uint256 expectedAssets = strategy.previewRedeemAsset(address(weth), maxShares);

        uint256 convertedAssets = strategy.previewMintAsset(address(weth), maxShares);

        vm.prank(alice);
        uint256 redeemedAmount = strategy.redeemAsset(address(weth), maxShares, alice, alice);

        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(redeemedAmount, convertedAssets, 1e14, "Redeemed amount should be total assets minus fee");

        assertEq(strategy.balanceOf(alice), shares - maxShares, "Alice should have correct shares remaining");
    }

    function test_Strategy_WithdrawAsset_notOwner(uint256 assets) public {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        uint256 expectedAssets = strategy.previewRedeemAsset(address(weth), maxShares);

        uint256 convertedAssets = strategy.previewMintAsset(address(weth), maxShares);
        uint256 redeemedAmount = strategy.withdrawAsset(address(weth), maxShares, address(this), alice);
        vm.stopPrank();

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(redeemedAmount, convertedAssets, 1e14, "Redeemed amount should be total assets minus fee");

        assertEq(strategy.balanceOf(address(this)), shares - maxShares, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Withdraw_notOwner(uint256 assets) public {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        uint256 expectedAssets = strategy.previewRedeem(maxShares);

        uint256 convertedAssets = strategy.previewMint(maxShares);
        vm.stopPrank();
        uint256 redeemedAmount = strategy.withdraw(maxShares, address(this), alice);

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(redeemedAmount, convertedAssets, 1e14, "Redeemed amount should be total assets minus fee");

        assertEq(strategy.balanceOf(address(this)), shares - maxShares, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Withdraw(uint256 assets) public {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        uint256 expectedAssets = strategy.previewRedeem(maxShares);

        uint256 convertedAssets = strategy.previewMint(maxShares);
        uint256 redeemedAmount = strategy.withdraw(maxShares, alice, alice);
        vm.stopPrank();

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(redeemedAmount, convertedAssets, 1e14, "Redeemed amount should be total assets minus fee");

        assertEq(strategy.balanceOf(alice), shares - maxShares, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Redeem(uint256 assets) public {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        uint256 expectedAssets = strategy.previewRedeem(maxShares);

        uint256 convertedAssets = strategy.previewMint(maxShares);
        uint256 redeemedAmount = strategy.redeem(maxShares, alice, alice);
        vm.stopPrank();

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(redeemedAmount, convertedAssets, 1e14, "Redeemed amount should be total assets minus fee");

        assertEq(strategy.balanceOf(alice), shares - maxShares, "Receiver should have correct shares remaining");
    }
}
