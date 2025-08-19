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

contract StrategyWithdrawUnitTest is Test, Etches, MainnetActors {
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

    function test_Strategy_WithdrawAsset_WithFees(uint256 assets, uint64 baseWithdrawalFee) external {
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        assets = bound(assets, 1000, 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.prank(alice);
        strategy.deposit(assets, alice);

        uint256 maxWithdraw = strategy.maxWithdrawAsset(address(weth), alice);
        uint256 previewRedeemAssets = strategy.previewRedeemAsset(address(weth), strategy.balanceOf(alice));

        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        if (strategy.maxWithdrawAsset(address(weth), alice) < maxWithdraw) {
            maxWithdraw = strategy.maxWithdrawAsset(address(weth), alice);
        }

        uint256 expectedFee = (maxWithdraw * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = strategy.convertToShares(maxWithdraw + expectedFee);
        uint256 feeShares = strategy.convertToShares(expectedFee);
        // Verify we can actually withdraw the max amount
        vm.prank(alice);
        uint256 withdrawnShares = strategy.withdrawAsset(address(weth), maxWithdraw, alice, alice);
        assertApproxEqAbs(withdrawnShares, expectedShares, 5, "Withdrawn shares should match expected");
        assertApproxEqAbs(strategy.balanceOf(alice), 0, 5, "Alice should have no shares remaining");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
    }

    function test_Strategy_WithdrawAsset_WithOverrideFee(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) external {
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(alice, overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        assets = bound(assets, 1000, 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.startPrank(alice);
        strategy.deposit(assets, alice);

        uint256 maxWithdraw = strategy.maxWithdrawAsset(address(weth), alice);
        uint256 previewRedeemAssets = strategy.previewRedeemAsset(address(weth), strategy.balanceOf(alice));

        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        if (strategy.maxWithdrawAsset(address(weth), alice) < maxWithdraw) {
            maxWithdraw = strategy.maxWithdrawAsset(address(weth), alice);
        }

        uint256 expectedFee = (maxWithdraw * overrideBaseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = strategy.convertToShares(maxWithdraw + expectedFee);
        uint256 feeShares = strategy.convertToShares(expectedFee);

        uint256 withdrawnShares = strategy.withdrawAsset(address(weth), maxWithdraw, alice, alice);
        assertApproxEqAbs(withdrawnShares, expectedShares, 5, "Withdrawn shares should match expected");
        assertApproxEqAbs(strategy.balanceOf(alice), 0, 5, "Alice should have no shares remaining");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
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

    function test_Strategy_RedeemAsset_WithFees(uint256 assets, uint64 baseWithdrawalFee) external {
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        assets = bound(assets, 1000, 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.startPrank(alice);
        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        uint256 expectedAssets = strategy.previewRedeemAsset(address(weth), maxShares);

        uint256 initialAliceBalance = weth.balanceOf(alice);

        uint256 redeemedAmount = strategy.redeemAsset(address(weth), maxShares, alice, alice);
        uint256 feeAmount = redeemedAmount * baseWithdrawalFee / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(feeAmount);

        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");
        assertEq(strategy.balanceOf(alice), shares - maxShares, "Alice should have correct shares remaining");
        assertApproxEqAbs(
            weth.balanceOf(alice), initialAliceBalance + redeemedAmount, 5, "Alice should have correct assets remaining"
        );
    }

    function test_Strategy_RedeemAsset_WithOverrideFee(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) external {
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(alice, overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        assets = bound(assets, 1000, 100_000 ether);

        vm.prank(alice);
        weth.approve(address(strategy), assets);

        vm.startPrank(alice);
        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        uint256 expectedAssets = strategy.previewRedeemAsset(address(weth), maxShares);

        uint256 initialAliceBalance = weth.balanceOf(alice);

        uint256 redeemedAmount = strategy.redeemAsset(address(weth), maxShares, alice, alice);
        uint256 feeAmount = redeemedAmount * overrideBaseWithdrawalFee / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(feeAmount);

        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");
        assertEq(strategy.balanceOf(alice), shares - maxShares, "Alice should have correct shares remaining");
        assertApproxEqAbs(
            weth.balanceOf(alice), initialAliceBalance + redeemedAmount, 5, "Alice should have correct assets remaining"
        );
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

    function test_Strategy_WithdrawAsset_WithFees_notOwner(uint256 assets, uint64 baseWithdrawalFee) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        if (maxShares > strategy.maxWithdrawAsset(address(weth), alice)) {
            maxShares = strategy.maxWithdrawAsset(address(weth), alice);
        }
        uint256 expectedFee = (maxShares * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);
        uint256 expectedAssets = strategy.convertToShares(maxShares + expectedFee);
        uint256 redeemedAmount = strategy.withdrawAsset(address(weth), maxShares, address(this), alice);
        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(address(this)), 0, "Receiver should have correct shares remaining");
        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedAssets, 5, "Redeemed amount should match preview");

        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
    }

    function test_Strategy_WithdrawAsset_WithOverrideFee_notOwner(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(alice, overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.depositAsset(address(weth), assets, alice);

        uint256 maxShares = strategy.maxRedeemAsset(address(weth), alice);
        if (maxShares > strategy.maxWithdrawAsset(address(weth), alice)) {
            maxShares = strategy.maxWithdrawAsset(address(weth), alice);
        }
        uint256 expectedFee = (maxShares * overrideBaseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);
        uint256 expectedAssets = strategy.convertToShares(maxShares + expectedFee);
        uint256 redeemedAmount = strategy.withdrawAsset(address(weth), maxShares, address(this), alice);
        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(address(this)), 0, "Receiver should have correct shares remaining");
        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedAssets, 5, "Redeemed amount should match preview");

        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
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

    function test_Strategy_Withdraw_WithFees_notOwner(uint256 assets, uint64 baseWithdrawalFee) public {
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxWithdraw(alice)) {
            maxShares = strategy.maxWithdraw(alice);
        }

        uint256 expectedFee = (maxShares * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);
        uint256 expectedSharesBurned = strategy.convertToShares(maxShares + expectedFee);

        vm.stopPrank();
        uint256 redeemedAmount = strategy.withdraw(maxShares, address(this), alice);

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedSharesBurned, 5, "Redeemed amount should match preview");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(address(this)), 0, "Receiver should have correct shares remaining");
        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Withdraw_WithOverrideFee_notOwner(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) public {
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(address(this), overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);
        strategy.approve(address(this), type(uint256).max);

        uint256 shares = strategy.deposit(assets, alice);
        vm.stopPrank();

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxWithdraw(alice)) {
            maxShares = strategy.maxWithdraw(alice);
        }

        uint256 expectedFee = (maxShares * overrideBaseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);
        uint256 expectedSharesBurned = strategy.convertToShares(maxShares + expectedFee);

        uint256 redeemedAmount = strategy.withdraw(maxShares, address(this), alice);

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedSharesBurned, 5, "Redeemed amount should match preview");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(address(this)), 0, "Receiver should have correct shares remaining");
        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
        vm.stopPrank();
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

    function test_Strategy_Withdraw_WithFees(uint256 assets, uint64 baseWithdrawalFee) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxWithdraw(alice)) {
            maxShares = strategy.maxWithdraw(alice);
        }
        uint256 expectedFee = (maxShares * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedSharesBurned = strategy.convertToShares(maxShares + expectedFee);
        uint256 feeShares = strategy.convertToShares(expectedFee);

        uint256 redeemedAmount = strategy.withdraw(maxShares, alice, alice);
        vm.stopPrank();

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedSharesBurned, 5, "Redeemed amount should match preview");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Withdraw_WithOverrideFee(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);

        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(alice, overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxWithdraw(alice)) {
            maxShares = strategy.maxWithdraw(alice);
        }
        uint256 expectedFee = (maxShares * overrideBaseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedSharesBurned = strategy.convertToShares(maxShares + expectedFee);
        uint256 feeShares = strategy.convertToShares(expectedFee);

        uint256 redeemedAmount = strategy.withdraw(maxShares, alice, alice);
        vm.stopPrank();

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertApproxEqAbs(redeemedAmount, expectedSharesBurned, 5, "Redeemed amount should match preview");
        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertEq(strategy.balanceOf(alice), shares - redeemedAmount, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Withdrawable_Asset_Revert_NotWithdrawable(uint256 assets) public {
        vm.assume(assets >= 1000 && assets <= 100_000 ether);
        uint256 shares = depositIntoStrategy(address(weth), alice, assets);
        // assert withdrawable assets are equal to shares when asset is withdrawable
        assertEq(
            strategy.maxWithdrawAsset(address(weth), alice), shares, "withdrawable Assets should be equal to assets"
        );

        // set asset to not withdrawable
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), false);

        assertEq(
            strategy.maxWithdrawAsset(address(weth), alice),
            0,
            "withdrawable Assets should be 0 after asset is set to not withdrawable"
        );

        vm.startPrank(alice);
        // withdraw
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, alice, shares, 0));
        strategy.withdrawAsset(address(weth), shares, alice, alice);
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

    function test_Strategy_Redeem_WithFees(uint256 assets, uint64 baseWithdrawalFee) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxRedeem(alice)) {
            maxShares = strategy.maxRedeem(alice);
        }
        uint256 initialAliceBalance = weth.balanceOf(alice);
        uint256 redeemedAmount = strategy.redeem(maxShares, alice, alice);

        uint256 expectedFee = (redeemedAmount * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);

        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertEq(
            weth.balanceOf(alice), initialAliceBalance + redeemedAmount, "Alice should have correct assets remaining"
        );
        assertEq(strategy.balanceOf(alice), shares - maxShares, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Redeem_WithOverrideFee(
        uint256 assets,
        uint64 baseWithdrawalFee,
        uint64 overrideBaseWithdrawalFee
    ) public {
        // Bound inputs to valid ranges
        assets = bound(assets, 1000, 100_000 ether);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideBaseWithdrawalFee = uint64(bound(overrideBaseWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        strategy.setBaseWithdrawalFee(baseWithdrawalFee);
        strategy.overrideBaseWithdrawalFee(alice, overrideBaseWithdrawalFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(strategy), assets);

        uint256 shares = strategy.deposit(assets, alice);

        uint256 maxShares = strategy.maxRedeem(alice);
        if (maxShares > strategy.maxRedeem(alice)) {
            maxShares = strategy.maxRedeem(alice);
        }
        uint256 initialAliceBalance = weth.balanceOf(alice);
        uint256 redeemedAmount = strategy.redeem(maxShares, alice, alice);

        uint256 expectedFee = (redeemedAmount * overrideBaseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = strategy.convertToShares(expectedFee);

        vm.stopPrank();

        assertApproxEqAbs(
            strategy.balanceOf(IFeeHooks(address(strategy.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );

        assertGt(redeemedAmount, 0, "Redeemed amount should be greater than 0");
        assertEq(
            weth.balanceOf(alice), initialAliceBalance + redeemedAmount, "Alice should have correct assets remaining"
        );
        assertEq(strategy.balanceOf(alice), shares - maxShares, "Receiver should have correct shares remaining");
    }

    function test_Strategy_Redeem_Asset_Revert_NotWithdrawable(uint256 assets) public {
        vm.assume(assets >= 1000 && assets <= 100_000 ether);
        uint256 shares = depositIntoStrategy(address(weth), alice, assets);
        assertEq(strategy.maxRedeemAsset(address(weth), alice), shares, "redeemable Assets should be equal to assets");
        // set asset to not withdrawable
        vm.prank(ASSET_MANAGER);
        strategy.setAssetWithdrawable(address(weth), false);
        assertEq(
            strategy.maxRedeemAsset(address(weth), alice),
            0,
            "redeemable Assets should be 0 after asset is set to not withdrawable"
        );
        // assert redeem should revert
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxRedeem.selector, alice, shares, 0));
        strategy.redeemAsset(address(weth), shares, alice, alice);
    }

    function depositIntoStrategy(address assetAddress, address depositor, uint256 amount)
        internal
        returns (uint256 shares)
    {
        IERC20 asset = IERC20(assetAddress);

        uint256 beforeTotalAssets = strategy.totalAssets();
        uint256 beforeTotalShares = strategy.totalSupply();
        uint256 beforeStrategyBalance = asset.balanceOf(address(strategy));
        uint256 beforeDepositorBalance = asset.balanceOf(depositor);
        uint256 beforeDepositorShares = strategy.balanceOf(depositor);
        uint256 beforeMaxWithdraw = strategy.maxWithdrawAsset(assetAddress, depositor);
        assertEq(beforeMaxWithdraw, 0, "Depositor should have no max withdraw before deposit");

        uint256 previewShares = strategy.previewDepositAsset(assetAddress, amount);

        vm.prank(depositor);
        asset.approve(address(strategy), amount);

        // Test the deposit function
        vm.prank(depositor);
        shares = strategy.depositAsset(assetAddress, amount, depositor);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        assertEq(
            strategy.totalAssets(),
            beforeTotalAssets + strategy.convertToAssets(shares),
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            strategy.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );

        assertEq(
            asset.balanceOf(address(strategy)),
            beforeStrategyBalance + amount,
            "Strategy should have the asset after deposit"
        );
        assertEq(asset.balanceOf(depositor), beforeDepositorBalance - amount, "From should not have the assets");
        assertEq(strategy.balanceOf(depositor), beforeDepositorShares + shares, "From should have shares after deposit");
        assertApproxEqAbs(
            strategy.maxWithdrawAsset(address(asset), depositor),
            beforeMaxWithdraw + amount,
            2,
            "Depositor should have max withdraw after deposit"
        );
    }

    function withdrawFromStrategy(address assetAddress, address withdrawer, uint256 withdrawAmount) internal virtual {
        IERC20 asset = IERC20(assetAddress);

        // Initial balances
        uint256 withdrawerAssetBefore = asset.balanceOf(withdrawer);
        uint256 withdrawerSharesBefore = strategy.balanceOf(withdrawer);

        // Store initial state
        uint256 initialTotalAssets = strategy.totalAssets();
        uint256 initialTotalSupply = strategy.totalSupply();

        // Store initial strategy Asset balance
        uint256 strategyAssetBefore = asset.balanceOf(address(strategy));

        vm.startPrank(withdrawer);

        // Deposit Asset to get shares
        uint256 shares = strategy.withdrawAsset(address(asset), withdrawAmount, withdrawer, withdrawer);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(withdrawer), withdrawerAssetBefore + withdrawAmount, "Asset balance incorrect");
        assertEq(strategy.balanceOf(withdrawer), withdrawerSharesBefore - shares, "Should have burnt shares");

        // Check strategy state after deposit
        assertEq(
            strategy.totalAssets(),
            initialTotalAssets - withdrawAmount,
            "Total assets should decrease by withdraw amount"
        );
        assertEq(strategy.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that strategy Asset balance increased by deposit amount
        assertEq(
            asset.balanceOf(address(strategy)),
            strategyAssetBefore - withdrawAmount,
            "Strategy balance should decrease by withdraw amount"
        );
    }

    function test_Strategy_Deposit_WETH(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        deal(address(weth), alice, assets);
        depositIntoStrategy(address(weth), alice, assets);
    }

    function test_Strategy_Withdraw_WETH(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        deal(address(weth), alice, assets);
        depositIntoStrategy(address(weth), alice, assets);
        withdrawFromStrategy(address(weth), alice, assets);
    }
}
