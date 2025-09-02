// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";

contract VaultWithdrawFeesUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);
    address public feeExemptedUser = makeAddr("feeExemptedUser");

    uint256 public constant INITIAL_BALANCE = 500_000 ether;
    uint256 public bufferRatio = 10_000_000;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Give Alice some tokens
        deal(address(weth), alice, INITIAL_BALANCE);
        deal(address(weth), feeExemptedUser, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(feeExemptedUser);
        weth.approve(address(vault), type(uint256).max);

        // Set base withdrawal fee to 0.1% (0.1% * 1e8)
        vm.prank(ADMIN);
        vault.setBaseWithdrawalFee(100_000);

        vm.prank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(feeExemptedUser, 0, true);
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function test_Vault_previewRedeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);

        uint256 redeemedPreview = vault.previewRedeem(withdrawnShares);
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqRel(
            redeemedPreview, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_Vault_previewRedeemWithOverriddenFee(uint256 assets, uint256 amountToRedeem, uint64 overriddenFee)
        external
    {
        // Bound inputs to valid ranges
        assets = bound(assets, 100000, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);

        vm.prank(alice);
        vault.deposit(assets, alice);

        amountToRedeem = bound(amountToRedeem, 100000, vault.balanceOf(alice));

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        vm.startPrank(alice);

        if (amountToRedeem > vault.maxRedeem(alice)) {
            amountToRedeem = vault.maxRedeem(alice);
        }
        uint256 amountWithoutFee = vault.convertToAssets(amountToRedeem);
        uint256 assetsReceived = vault.previewRedeem(amountToRedeem);
        uint256 expectedFee = (assetsReceived * overriddenFee) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(assetsReceived, amountWithoutFee - expectedFee, 5, "Withdrawal fee should be overridden fee");
        vm.stopPrank();
    }

    function test_Vault_previewRedeemWithExemptedFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        vm.startPrank(feeExemptedUser);
        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);

        uint256 redeemedPreview = vault.previewRedeem(withdrawnShares);
        assertEq(redeemedPreview, withdrawnAssets, "Withdrawal fee should be 0 for users exempted from fees");
    }

    function test_Vault_previewWithdrawWithFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawPreview = vault.previewWithdraw(withdrawnAssets);
        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.convertToShares(withdrawnAssets + expectedFee);
        assertApproxEqAbs(withdrawPreview, expectedShares, 1, "Preview withdraw shares should match expected");
    }

    function test_Vault_previewWithdrawWithOverriddenFee(uint256 assets, uint256 withdrawnAssets, uint64 overriddenFee)
        external
    {
        assets = bound(assets, 100000, 100_000 ether);
        withdrawnAssets = bound(withdrawnAssets, 0, assets);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        if (withdrawnAssets > vault.maxWithdraw(alice)) {
            withdrawnAssets = vault.maxWithdraw(alice);
        }

        vm.startPrank(alice);
        uint256 withdrawPreview = vault.previewWithdraw(withdrawnAssets);
        uint256 expectedFee = (withdrawnAssets * overriddenFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.convertToShares(withdrawnAssets + expectedFee);
        assertApproxEqAbs(withdrawPreview, expectedShares, 5, "Preview withdraw shares should match expected");
    }

    function test_Vault_previewWithdrawWithFeesExempted(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        vm.startPrank(feeExemptedUser);
        uint256 withdrawPreview = vault.previewWithdraw(withdrawnAssets);
        uint256 expectedShares = vault.convertToShares(withdrawnAssets);

        assertApproxEqAbs(withdrawPreview, expectedShares, 1, "Preview withdraw shares should match expected");
    }

    function test_Vault_redeemWithFeesMaxAmount(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.prank(alice);
        vault.deposit(assets, alice);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        uint256 maxShares = vault.maxRedeem(alice);
        uint256 expectedAssets = vault.previewRedeem(maxShares);

        uint256 convertedAssets = vault.convertToAssets(maxShares);
        uint256 expectedFee = (expectedAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;

        vm.prank(alice);
        uint256 redeemedAmount = vault.redeem(maxShares, alice, alice);

        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(
            redeemedAmount, convertedAssets - expectedFee, 1e14, "Redeemed amount should be total assets minus fee"
        );

        assertEq(vault.balanceOf(alice), 0, "Alice should have no shares remaining");
    }

    function test_Vault_redeemWithExemptedFeesMaxAmount(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        vm.startPrank(feeExemptedUser);
        uint256 maxShares = vault.maxRedeem(feeExemptedUser);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 expectedAssets = vault.previewRedeem(maxShares);
        uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());

        uint256 convertedAssets = vault.convertToAssets(maxShares);
        uint256 redeemedAmount = vault.redeem(maxShares, feeExemptedUser, feeExemptedUser);
        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertApproxEqAbs(exchangeRateAfter, exchangeRateBefore, 5, "exchange rate should not change");

        assertApproxEqAbs(
            totalSupplyAfter,
            totalSupplyBefore - maxShares,
            1,
            "Vault total supply should not change after redeem for fee exempted user"
        );
        assertApproxEqAbs(redeemedAmount, expectedAssets, 1, "Redeemed amount should match preview");

        assertApproxEqAbs(redeemedAmount, convertedAssets, 1, "Redeemed amount should be total assets minus fee");

        assertEq(vault.balanceOf(feeExemptedUser), 0, "Alice should have no shares remaining");
    }

    function test_Vault_maxWithdrawWithFullBuffer(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        //uint256 assets = 117300740;

        vm.prank(alice);
        vault.deposit(assets, alice);

        // Allocate full amount to buffer
        vm.prank(ADMIN);
        allocateToBuffer(assets);

        uint256 maxWithdraw = vault.maxWithdraw(alice);
        uint256 previewRedeemAssets = vault.previewRedeem(vault.balanceOf(alice));

        // Since buffer has full amount, maxWithdraw should equal previewRedeemAssets
        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        uint256 expectedFee = (maxWithdraw * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.convertToShares(maxWithdraw + expectedFee);

        // Verify we can actually withdraw the max amount
        vm.prank(alice);
        uint256 withdrawnShares = vault.withdraw(maxWithdraw, alice, alice);

        assertApproxEqAbs(withdrawnShares, expectedShares, 2, "Withdrawn shares should match expected with fee");
        assertApproxEqAbs(vault.balanceOf(alice), 0, 1, "Alice should have no shares remaining");
    }

    function test_Vault_maxWithdrawWithFullBufferFeesExempted(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        // Allocate full amount to buffer
        vm.prank(ADMIN);
        allocateToBuffer(assets);

        vm.startPrank(feeExemptedUser);
        uint256 maxWithdraw = vault.maxWithdraw(feeExemptedUser);
        uint256 previewRedeemAssets = vault.previewRedeem(vault.balanceOf(feeExemptedUser));

        // Since buffer has full amount, maxWithdraw should equal previewRedeemAssets
        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        uint256 expectedShares = vault.convertToShares(maxWithdraw);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        // Verify we can actually withdraw the max amount
        uint256 withdrawnShares = vault.withdraw(maxWithdraw, feeExemptedUser, feeExemptedUser);

        uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertApproxEqAbs(exchangeRateAfter, exchangeRateBefore, 5, "exchange rate should not change");

        assertApproxEqAbs(
            vault.totalSupply(), totalSupplyBefore - maxWithdraw, 1, "Vault total supply should decrease after withdraw"
        );
        assertApproxEqAbs(withdrawnShares, expectedShares, 1, "Withdrawn shares should match expected with fee");
        assertApproxEqAbs(vault.balanceOf(feeExemptedUser), 0, 2, "feeExemptedUser should have no shares remaining");
    }

    function test_Vault_redeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.deposit(assets, alice);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);

        vm.prank(alice);
        uint256 redeemedAmount = vault.redeem(withdrawnShares, alice, alice);
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqRel(
            redeemedAmount, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_Vault_redeemWithExemptedFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        vm.startPrank(feeExemptedUser);
        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);
        uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 redeemedAmount = vault.redeem(withdrawnShares, feeExemptedUser, feeExemptedUser);
        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertApproxEqAbs(exchangeRateAfter, exchangeRateBefore, 5, "exchange rate should not change");

        assertApproxEqAbs(
            vaultTotalSupplyAfter,
            vaultTotalSupplyBefore - withdrawnShares,
            1,
            "Vault total supply should decrease after redeem"
        );
        assertEq(redeemedAmount, withdrawnAssets, "Withdrawal fee should be 0 for users exempted from fees");
    }

    function test_Vault_withdrawWithExemptedFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 10_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        vm.startPrank(feeExemptedUser);
        uint256 maxWithdraw = vault.maxWithdraw(feeExemptedUser);
        if (withdrawnAssets > maxWithdraw) {
            withdrawnAssets = maxWithdraw;
        }

        uint256 expectedSharesToBurn = vault.convertToShares(withdrawnAssets);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 withdrawAmount = vault.withdraw(withdrawnAssets, feeExemptedUser, feeExemptedUser);
        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertApproxEqAbs(exchangeRateAfter, exchangeRateBefore, 5, "exchange rate should not change");

        assertApproxEqAbs(
            totalSupplyAfter, totalSupplyBefore - withdrawAmount, 1, "Vault total supply should decrease after withdraw"
        );
        assertApproxEqAbs(withdrawAmount, expectedSharesToBurn, 2, "Preview withdraw shares should match expected");
    }

    function test_Vault_feeOnRaw_FlatFee(uint256 assets) external {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawnAssets = maxBufferAssets / 2;

        uint256 fee = vault._feeOnRaw(withdrawnAssets, alice);

        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be 0.1% of assets");
    }

    function test_Vault_feeOnRaw_OverridenFees(uint256 assets, uint64 overriddenFee) external {
        assets = bound(assets, 100000, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawnAssets = maxBufferAssets / 2;

        uint256 fee = vault._feeOnRaw(withdrawnAssets, alice);

        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * overriddenFee) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be same as expected fees");

        vm.startPrank(FEE_MANAGER);
        vault.overrideBaseWithdrawalFee(alice, 0, false);
        vm.stopPrank();

        fee = vault._feeOnRaw(withdrawnAssets, alice);
        expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be same as expected fees");
    }

    function test_Vault_feeOnRaw_ExemptedFee(uint256 assets) external {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        vm.startPrank(feeExemptedUser);
        uint256 withdrawnAssets = maxBufferAssets / 2;

        uint256 fee = vault._feeOnRaw(withdrawnAssets, feeExemptedUser);

        // Base withdrawal fee is 0.1% (100_000)
        // since feeExemptedUser is exempted from fees, fee should be 0
        uint256 expectedFee = 0;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be 0");
    }

    function test_Vault_feeOnTotal_ExemptedFee(uint256 assets) external {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(feeExemptedUser);
        vault.deposit(assets, feeExemptedUser);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        vm.startPrank(feeExemptedUser);
        uint256 withdrawnAssets = maxBufferAssets / 2;

        uint256 fee = vault._feeOnTotal(withdrawnAssets, feeExemptedUser);

        // Base withdrawal fee is 0.1% (100_000)
        // since feeExemptedUser is exempted from fees, fee should be 0
        uint256 expectedFee = 0;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be 0");
    }

    function skiptest_Vault_withdraw_success(uint256 assets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        uint256 depositShares = vault.deposit(assets, alice);

        allocateToBuffer(assets);
        uint256 previewAmount = vault.previewWithdraw(assets);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdraw(assets, alice, alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceBalanceAfter = vault.balanceOf(alice);

        assertEq(aliceBalanceBefore, aliceBalanceAfter + shares, "Alice's balance should be less the shares withdrawn");
        assertEq(previewAmount, shares, "Preview withdraw amount not preview amount");
        assertEq(depositShares, shares, "Deposit shares not match with withdraw shares");
        assertLt(totalAssetsAfter, totalAssetsBefore, "Total assets should be less after withdraw");
        assertEq(
            totalAssetsBefore,
            totalAssetsAfter + assets,
            "Total assets should be total assets after plus assets withdrawn"
        );
    }
}
