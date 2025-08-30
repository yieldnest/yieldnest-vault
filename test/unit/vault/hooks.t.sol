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
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {FeeHooks} from "src/module/FeeHooks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "src/Common.sol";
import {console} from "lib/forge-std/src/console.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";

contract HooksUnitTest is Test, MainnetActors, Etches, AssertUtils {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;

    WETH9 public weth;
    MockSTETH public steth;
    FeeHooks public hooks;

    address public alice = address(0x1);
    address public caller = address(0x2);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        hooks = FeeHooks(address(vault.hooks()));

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        deal(caller, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(caller, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(caller);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_ProcessAccounting_Scenario() public {
        // alice deposits 1 ether to vault
        vm.startPrank(alice);
        uint256 shares = vault.deposit(1 ether, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether, "vault's total assets should be 1 ether");

        uint256 yield = 0.1 ether;

        // alice transfers 10% of vault's balance to vault which will be considered as yield
        weth.transfer(address(vault), yield);

        uint256 performanceFee = yield * hooks.performanceFee() / 1 ether;
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        vault.processAccounting();

        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;
        assertApproxEqAbs(
            vault.convertToAssets(performanceFeeSharesReceived),
            performanceFee,
            5,
            "performance fee shares received should be equal to performance fee"
        );
        assertEq(
            vault.totalSupply(),
            shares + performanceFeeSharesReceived,
            "vault's total supply should be equal to shares + performance fee shares received"
        );
        assertEq(vault.totalAssets(), 1 ether + yield, "vault's total assets should be equal to 1 ether + yield");
    }

    function test_ProcessAccounting_Yield_Same_As_TotalAssets() public {
        uint256 performanceFeeWad = 1 ether;

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(performanceFeeWad);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(1 ether, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether, "vault's total assets should be 1 ether");
        assertEq(shares, 1 ether, "shares should be 1 ether");

        uint256 yield = 1 ether;
        weth.transfer(address(vault), yield);

        uint256 performanceFee = yield;
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        vault.processAccounting();
        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;
        assertEq(performanceFeeSharesReceived, 1 ether, "performance fee shares received should be 1 ether");
        assertEq(
            vault.convertToAssets(performanceFeeSharesReceived),
            performanceFee,
            "performance fee shares received should be equal to performance fee"
        );
        assertEq(vault.totalSupply(), 2 ether, "vault's total supply should be 2 ether");
        assertEq(vault.totalAssets(), 2 ether, "vault's total assets should be 2 ether");
    }

    function test_ProcessAccounting_Zero_Yield() public {
        vm.startPrank(alice);
        uint256 shares = vault.deposit(1 ether, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether, "vault's total assets should be 1 ether");
        assertEq(shares, 1 ether, "shares should be 1 ether");

        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        vault.processAccounting();
        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;
        assertEq(performanceFeeSharesReceived, 0, "performance fee shares received should be 0");
        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether, "vault's total assets should be 1 ether");
    }

    function test_ProcessAccounting_Zero_Performance_Fee() public {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(1 ether, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether, "vault's total assets should be 1 ether");
        assertEq(shares, 1 ether, "shares should be 1 ether");

        uint256 yield = 0.1 ether;
        weth.transfer(address(vault), yield);

        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        vault.processAccounting();
        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        assertEq(
            performanceFeeRecipientSharesAfter,
            performanceFeeRecipientSharesBefore,
            "performance fee recipient shares should be 0"
        );
        assertEq(performanceFeeRecipientSharesAfter, 0, "performance fee recipient shares should be 0");
        assertEq(vault.totalSupply(), 1 ether, "vault's total supply should be 1 ether");
        assertEq(vault.totalAssets(), 1 ether + yield, "vault's total assets should be 1 ether + yield");
    }

    function test_AfterProcessAccounting_Invariants(
        uint256 totalAssetsBefore,
        uint256 totalAssetsAfter,
        uint256 performanceFee
    ) public {
        totalAssetsBefore = bound(totalAssetsBefore, 1 ether, 1_000_000_000 ether);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 1 ether, 1_000_000_001 ether);
        performanceFee = bound(performanceFee, 0.01 ether, 1 ether);

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(performanceFee);
        vm.stopPrank();

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 18);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        deal((MC.WETH), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.WETH).transfer(address(vault), donationAmount);
        vm.stopPrank();

        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 feesAccrued = (donationAmount * hooks.performanceFee()) / 1 ether;

        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        if (feesAccrued > 0) {
            assertGt(
                vaultTotalSupplyAfter,
                vaultTotalSupplyBefore,
                "vault's total supply should increase due to fee shares minted"
            );
            uint256 performanceFeeShares = vaultTotalSupplyAfter - vaultTotalSupplyBefore;
            assertEq(
                performanceFeeShares,
                vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
                "performance fee shares should be equal to performance fee recipient's balance"
            );
            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                1e12,
                "performance fee shares should be equal to performance fee amount"
            );
        } else {
            assertEq(
                vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee"
            );
        }
        assertGe(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );
    }

    function test_AfterProcessingAccountWithNoPerformanceFee(uint256 totalAssetsBefore, uint256 totalAssetsAfter)
        public
    {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0);
        vm.stopPrank();

        totalAssetsBefore = bound(totalAssetsBefore, 1 ether, 1_000_000_000 ether);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 1 ether, 1_000_000_002 ether);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 18);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        deal((MC.WETH), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.WETH).transfer(address(vault), donationAmount);
        vm.stopPrank();

        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());

        assertEq(vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee");
        assertGt(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );

        vm.stopPrank();
    }

    function test_AfterProcessAccounting_MultipleDeposits(
        uint256 depositAmount1,
        uint256 depositAmount2,
        uint256 yieldAmount1,
        uint256 performanceFee
    ) public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        depositAmount1 = bound(depositAmount1, 1 ether, 10_000 ether);
        depositAmount2 = bound(depositAmount2, 1 ether, 10_000 ether);
        yieldAmount1 = bound(yieldAmount1, 1 ether, 10_000 ether);
        performanceFee = bound(performanceFee, 0.01 ether, 1 ether);

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(performanceFee);
        vm.stopPrank();

        deal((MC.WETH), user1, depositAmount1);
        deal((MC.WETH), user2, depositAmount2 + yieldAmount1);

        vm.startPrank(user1);
        IERC20(MC.WETH).approve(address(vault), depositAmount1);
        uint256 shares1 = vault.deposit(depositAmount1, user1);
        vault.processAccounting();
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(MC.WETH).approve(address(vault), depositAmount2);
        uint256 shares2 = vault.deposit(depositAmount2, user2);
        vault.processAccounting();
        IERC20(MC.WETH).transfer(address(vault), yieldAmount1);
        vm.stopPrank();

        uint256 performanceFeeShares;
        uint256 performanceFeeAmount;
        {
            performanceFeeAmount = (yieldAmount1 * performanceFee) / 1 ether;
            uint256 sharesOfFeeRecipientBefore =
                vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
            vault.processAccounting();
            uint256 sharesOfFeeRecipientAfter =
                vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
            performanceFeeShares = sharesOfFeeRecipientAfter - sharesOfFeeRecipientBefore;
        }

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertApproxEqAbs(
            vault.convertToAssets(performanceFeeShares),
            performanceFeeAmount,
            1e12,
            "performance fee shares should be equal to performance fee amount"
        );
        assertEqThreshold(
            totalAssets, depositAmount1 + depositAmount2 + yieldAmount1, 5000, "totalAssets should match expected"
        );
        assertEqThreshold(
            totalSupply, shares1 + shares2 + performanceFeeShares, 5000, "totalSupply should match expected"
        );

        assertEqThreshold(
            vault.balanceOf(FEE_MANAGER),
            performanceFeeShares,
            5000,
            "FEE_MANAGER should have the performance fee shares"
        );
    }

    function test_AfterProcessAccounting_WithoutYield(uint256 wethAmount) public {
        // Bound inputs to reasonable ranges
        wethAmount = bound(wethAmount, 1 ether, 10_000 ether);

        // Initial deposit of WETH through deposit function
        vm.startPrank(alice);
        uint256 shares = vault.deposit(wethAmount, alice);
        uint256 expectedTotalAssets = wethAmount;
        uint256 expectedTotalSupply = shares;
        vm.stopPrank();

        uint256 totalSupplyBeforeProcessing = vault.totalSupply();

        vault.processAccounting();

        uint256 totalSupplyAfterProcessing = vault.totalSupply();

        assertEq(
            totalSupplyBeforeProcessing, totalSupplyAfterProcessing, "totalSupply should stay the same due to no yield"
        );

        uint256 totalAssets = vault.totalAssets();

        assertEq(vault.balanceOf(FEE_MANAGER), 0, "FEE_MANAGER should have no shares");
        assertEqThreshold(totalAssets, expectedTotalAssets, 5000, "totalAssets should match expected");
        assertEqThreshold(totalSupplyBeforeProcessing, expectedTotalSupply, 5000, "totalSupply should match expected");
    }

    function test_afterRedeem_Increases_Shares(uint256 sharesAmount) public {
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);

        sharesAmount = bound(sharesAmount, 0.001 ether, 100_000 ether);
        vm.startPrank(alice);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(MC.WETH, sharesAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "totalSupply should increase");
    }

    function test_afterRedeem_ExemptedFromFee(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, 0, true);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(MC.WETH, shares, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase due to fee exemption");
    }

    function test_afterRedeem_OverriddenFee(uint256 depositAmount, uint64 overriddenFee) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(MC.WETH, shares, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "totalSupply should increase due to fee overriden");
    }

    function test_afterWithdraw_Increases_Shares(uint256 sharesAmount) public {
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);

        sharesAmount = bound(sharesAmount, 0.001 ether, 100_000 ether);
        vm.startPrank(alice);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(MC.WETH, sharesAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfterBeforeWithdraw = vault.totalSupply();
        assertEq(totalSupplyAfterBeforeWithdraw, totalSupplyBefore, "totalSupply should increase by sharesAmount");

        vm.startPrank(address(vault));
        hooks.afterWithdraw(MC.WETH, sharesAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "totalSupply should increase by sharesAmount");
    }

    function test_beforeWithdraw_ExemptedFromFee(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, 0, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(MC.WETH, depositAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase due to fee exemption");
    }

    function test_beforeWithdraw_and_afterWithdraw_OverriddenFee(uint256 depositAmount, uint64 overriddenFee) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(MC.WETH, depositAmount, alice, alice, alice, 0);
        hooks.afterWithdraw(MC.WETH, depositAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "totalSupply should increase due to fee overriden");
    }

    function test_beforeWithdraw_MintsToFeeRecipient(
        uint256 depositAmount,
        uint256 yieldAmount,
        uint256 withdrawalAmount,
        uint64 withdrawalFee
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        yieldAmount = bound(yieldAmount, 1 ether, 100 ether);
        withdrawalAmount = bound(withdrawalAmount, 10000, depositAmount - 1000);
        withdrawalFee = uint64(bound(withdrawalFee, 0, 1e8 / 2));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        weth.transfer(address(vault), yieldAmount);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(MC.WETH, withdrawalAmount, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 sharesMinted = vaultBalanceOfPerformanceFeeRecipientAfter - vaultBalanceOfPerformanceFeeRecipientBefore;

        assertEq(totalSupplyAfter, totalSupplyBefore + sharesMinted, "total supply should increase by shares minted");
    }

    function test_afterRedeem_MintsToFeeRecipient(
        uint256 depositAmount,
        uint256 yieldAmount,
        uint256 withdrawalAmount,
        uint64 withdrawalFee
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        yieldAmount = bound(yieldAmount, 1 ether, 100 ether);
        withdrawalAmount = bound(withdrawalAmount, 10000, depositAmount - 1000);
        withdrawalFee = uint64(bound(withdrawalFee, 0, 1e8 / 2));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        vm.startPrank(address(vault));
        hooks.afterRedeem(MC.WETH, shares, alice, alice, alice, 0);
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 sharesMinted = vaultBalanceOfPerformanceFeeRecipientAfter - vaultBalanceOfPerformanceFeeRecipientBefore;

        assertEq(totalSupplyAfter, totalSupplyBefore + sharesMinted, "total supply should increase by shares minted");
    }

    function test_AfterProcessAccounting_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(1 ether, 1 ether, 1 ether, 0, 0, 0);
        vm.stopPrank();
    }

    function test_beforeWithdraw_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeWithdraw(MC.WETH, 1 ether, alice, alice, alice, 0);
        vm.stopPrank();
    }

    function test_afterRedeem_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterRedeem(MC.WETH, 1 ether, alice, alice, alice, 0);
        vm.stopPrank();
    }

    function test_HooksFunction_OnlyCallableByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeDeposit(MC.WETH, 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterDeposit(MC.WETH, 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeMint(MC.WETH, 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterMint(MC.WETH, 1 ether, alice, alice, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeRedeem(MC.WETH, 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterRedeem(MC.WETH, 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeWithdraw(MC.WETH, 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterWithdraw(MC.WETH, 1 ether, alice, alice, alice, 0);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeProcessAccounting(1 ether, 1 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(1 ether, 1 ether, 1 ether, 0, 0, 0);
        vm.stopPrank();

        vm.startPrank(address(vault));
        hooks.beforeDeposit(MC.WETH, 1 ether, alice, alice, 0, 0);
        hooks.afterDeposit(MC.WETH, 1 ether, alice, alice, 0, 0);
        hooks.beforeMint(MC.WETH, 1 ether, alice, alice, 0, 0);
        hooks.afterMint(MC.WETH, 1 ether, alice, alice, 0, 0);
        hooks.beforeRedeem(MC.WETH, 1 ether, alice, alice, alice, 0);
        hooks.afterRedeem(MC.WETH, 1 ether, alice, alice, alice, 0);
        hooks.beforeWithdraw(MC.WETH, 1 ether, alice, alice, alice, 0);
        hooks.afterWithdraw(MC.WETH, 1 ether, alice, alice, alice, 0);
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
            address(hooks), abi.encodeCall(IHooks.beforeDeposit, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 1
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterDeposit, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 1
        );
        vault.deposit(1 ether, alice);
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
            address(hooks), abi.encodeCall(IHooks.beforeDeposit, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 0
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterDeposit, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 0
        );
        vault.deposit(1 ether, alice);
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
            address(hooks), abi.encodeCall(IHooks.beforeMint, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 1
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterMint, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 1
        );
        vault.mint(1 ether, alice);
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
            address(hooks), abi.encodeCall(IHooks.beforeMint, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 0
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterMint, (MC.WETH, 1 ether, caller, alice, 1 ether, 1 ether)), 0
        );
        vault.mint(1 ether, alice);
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
        uint256 depositShares = vault.deposit(1 ether, alice);

        allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        uint256 assetsToRedeem = vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.beforeRedeem, (MC.WETH, sharesToRedeem, alice, alice, alice, assetsToRedeem)),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterRedeem, (MC.WETH, sharesToRedeem, alice, alice, alice, assetsToRedeem)),
            1
        );
        vault.redeem(sharesToRedeem, alice, alice);
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
        uint256 depositShares = vault.deposit(1 ether, alice);

        allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to not be called
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.beforeRedeem, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 0
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterRedeem, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 0
        );
        vault.redeem(1 ether, alice, alice);
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
        uint256 depositShares = vault.deposit(1 ether, alice);
        vm.stopPrank();

        allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to be called by 1 time
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.beforeWithdraw, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 1
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterWithdraw, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 1
        );
        vault.withdraw(1 ether, alice, alice);
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
        uint256 depositShares = vault.deposit(1 ether, alice);
        vm.stopPrank();

        allocateToBuffer(1 ether);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to not be called
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.beforeWithdraw, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 0
        );
        vm.expectCall(
            address(hooks), abi.encodeCall(IHooks.afterWithdraw, (MC.WETH, 1 ether, alice, alice, alice, 1 ether)), 0
        );
        vault.withdraw(1 ether, alice, alice);
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
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to be called by 1 time
        vm.expectCall(address(hooks), abi.encodeCall(IHooks.beforeProcessAccounting, (1 ether, 1 ether, 1 ether)), 1);
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterProcessAccounting, (1 ether, 1 ether, 1 ether, 1 ether, 1 ether, 1 ether)),
            1
        );
        vault.processAccounting();
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
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to not be called
        vm.expectCall(address(hooks), abi.encodeCall(IHooks.beforeProcessAccounting, (1 ether, 1 ether, 1 ether)), 0);
        vm.expectCall(
            address(hooks),
            abi.encodeCall(IHooks.afterProcessAccounting, (1 ether, 1 ether, 1 ether, 1 ether, 1 ether, 1 ether)),
            0
        );
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_HooksNotSet() public {
        vm.prank(ADMIN);
        vault.setHooks(address(0));

        vm.startPrank(caller);
        vault.deposit(1 ether, alice);
        vault.mint(1 ether, alice);
        vm.stopPrank();
        allocateToBuffer(1 ether);

        vault.processAccounting();

        vm.startPrank(alice);
        vault.redeem(1 wei, alice, alice);
        vault.withdraw(1 wei, alice, alice);
        vm.stopPrank();

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
    }

    function test_setPerformanceFeeRecipient() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        vm.startPrank(ADMIN);
        hooks.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        assertEq(hooks.performanceFeeRecipient(), newPerformanceFeeRecipient);
    }

    function test_setPerformanceFeeRecipient_notAdmin() public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        hooks.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function test_setPerformanceFeeRecipient_invalidRecipient() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IFeeHooks.InvalidPerformanceFeeRecipient.selector));
        hooks.setPerformanceFeeRecipient(address(0));
    }

    function test_setPerformanceFee() public {
        uint256 newPerformanceFee = 1e16;
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(newPerformanceFee);
        assertEq(hooks.performanceFee(), newPerformanceFee);
    }

    function test_setPerformanceFee_notAdmin() public {
        uint256 newPerformanceFee = 1e16;
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        hooks.setPerformanceFee(newPerformanceFee);
    }

    function test_setPerformanceFee_invalidFee() public {
        uint256 newPerformanceFee = 1e19;
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IFeeHooks.InvalidPerformanceFee.selector));
        hooks.setPerformanceFee(newPerformanceFee);
    }

    function test_setHooks_revertsIfInvalidHooks() public {
        SetupVault setupVault = new SetupVault();
        (Vault dummyVault,) = setupVault.setup();
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
        address invalidHooks = address(new FeeHooks(address(dummyVault), ADMIN, 1e17, FEE_MANAGER, config));
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidHooks.selector));
        vault.setHooks(invalidHooks);
    }

    function test_setHooks_ZeroAddress() public {
        vm.startPrank(ADMIN);
        vault.setHooks(address(0));
        assertEq(address(vault.hooks()), address(0));
    }

    function allocateToBuffer(uint256 amount) internal {
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
}
