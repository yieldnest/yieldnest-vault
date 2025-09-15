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
import {TestHelpers} from "test/unit/helpers/TestHelpers.sol";
import {MathUtils} from "test/utils/MathUtils.sol";

contract FeeHooksUnitTest is Test, MainnetActors, Etches, AssertUtils {
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

    function test_ProcessAccounting_100_Percent_Performance_Fee_With_100_Percent_Yield() public {
        uint256 rateBefore = vault.convertToAssets(1e18);

        processAccounting_100_Percent_Performance_Fee(1 ether, 1 ether);

        uint256 rateAfter = vault.convertToAssets(1e18);
        assertEq(rateBefore, 1e18, "rate before should be 1e18");
        assertEq(rateAfter, 1e18, "rate after should be 1e18");

        assertEq(vault.totalAssets(), 2 ether, "vault's total assets should be 2 ether");
        assertEq(vault.totalSupply(), 2 ether, "vault's total supply should be 2 ether");
    }

    function test_Fuzz_ProcessAccounting_100_Percent_Performance_Fee(uint256 depositAmount, uint256 yield) public {
        depositAmount = bound(depositAmount, 1 ether, 10_000 ether);
        yield = bound(yield, 0, depositAmount * 10);
        processAccounting_100_Percent_Performance_Fee(depositAmount, yield);
    }

    function processAccounting_100_Percent_Performance_Fee(uint256 depositAmount, uint256 yield) public {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(1 ether); // 100% performance fee
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), depositAmount, "vault's total supply should be depositAmount");
        assertEq(vault.totalAssets(), depositAmount, "vault's total assets should be depositAmount");
        assertEq(shares, depositAmount, "shares should be depositAmount");

        weth.transfer(address(vault), yield);
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        uint256 convertToAssetsBefore = vault.convertToAssets(1e18);
        assertEq(convertToAssetsBefore, 1e18, "vault's convertToAssets should be 1e18");

        vault.processAccounting();

        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;
        uint256 convertToAssetsAfter = vault.convertToAssets(1e18);

        assertEq(convertToAssetsBefore, convertToAssetsAfter, "convertToAssets for 1e18 should stay the same");

        if (yield > 0) {
            // With 100% performance fee, all yield should go to fee recipient as shares
            uint256 expectedPerformanceFeeShares = vault.convertToShares(yield);
            assertEq(
                performanceFeeSharesReceived,
                expectedPerformanceFeeShares,
                "performance fee shares received should equal expected shares for 100% fee"
            );
            assertEq(
                vault.totalSupply(),
                depositAmount + performanceFeeSharesReceived,
                "vault's total supply should include fee shares"
            );
            assertEq(vault.totalAssets(), depositAmount + yield, "vault's total assets should be depositAmount + yield");

            // Alice's share value should remain the same (depositAmount worth of assets)
            uint256 aliceAssetValue = vault.convertToAssets(vault.balanceOf(alice));
            assertEq(aliceAssetValue, depositAmount, "Alice's asset value should remain depositAmount");
        } else {
            // With no yield, no performance fee should be collected
            assertEq(performanceFeeSharesReceived, 0, "performance fee shares received should be 0 with no yield");
            assertEq(vault.totalSupply(), depositAmount, "vault's total supply should remain depositAmount");
            assertEq(vault.totalAssets(), depositAmount, "vault's total assets should remain depositAmount");
        }
    }

    function test_ProcessAccounting_50_Percent_Performance_Fee_With_200_Percent_Yield() public {
        uint256 depositAmount = 1 ether;
        uint256 yield = 2 ether;

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0.5 ether); // 50% performance fee
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), depositAmount, "vault's total supply should be depositAmount");
        assertEq(vault.totalAssets(), depositAmount, "vault's total assets should be depositAmount");
        assertEq(shares, depositAmount, "shares should be depositAmount");

        weth.transfer(address(vault), yield);
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 convertToAssetsBefore = vault.convertToAssets(1e18);
        assertEq(convertToAssetsBefore, 1e18, "vault's convertToAssets should be 1e18");

        vault.processAccounting();

        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        assertApproxEqAbs(vault.convertToAssets(1e18), 2e18, 1, "vault's convertToAssets should be 2e18");

        // 50% fee applied to the shares equivalent of 2 ether in yield at a rate of 2e18
        // Therefore the 50% fee is applied to 1e18 shares = 0.5 ether

        assertEq(
            performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore,
            0.5 ether,
            "vault should have gained 0.5 ether in shares"
        );

        assertEq(vault.totalAssets(), 3 ether, "vault's total assets should be 3 ether");
        assertEq(vault.totalSupply(), 1.5 ether, "vault's total supply should be 2 ether");
    }

    function test_ProcessAccounting_20_Percent_Performance_Fee_With_100_Percent_Yield() public {
        uint256 depositAmount = 1 ether;
        uint256 yield = 1 ether;

        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0.2 ether); // 20% performance fee
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vault.processAccounting();

        assertEq(vault.totalSupply(), depositAmount, "vault's total supply should be depositAmount");
        assertEq(vault.totalAssets(), depositAmount, "vault's total assets should be depositAmount");
        assertEq(shares, depositAmount, "shares should be depositAmount");

        weth.transfer(address(vault), yield);
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 convertToAssetsBefore = vault.convertToAssets(1e18);
        assertEq(convertToAssetsBefore, 1e18, "vault's convertToAssets should be 1e18");

        vault.processAccounting();

        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;

        assertApproxEqAbs(vault.convertToAssets(1e18), 1.8 ether, 1, "vault's convertToAssets should be 1.8 ether");

        assertEq(
            performanceFeeSharesReceived,
            0.111111111111111111 ether,
            "vault should have gained 0.2 ether worth of shares"
        );

        assertEq(vault.totalAssets(), 2 ether, "vault's total assets should be 2 ether");
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

            assertLe(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                "performance fee shares should be less than or equal to performance fee amount"
            );

            if (vaultExchangeRateAfter < 3 ether) {
                // for a "normal" rate range.
                assertApproxEqAbs(
                    vault.convertToAssets(performanceFeeShares),
                    feesAccrued,
                    3,
                    "performance fee shares should be equal to performance fee amount"
                );
            }

            // The error is proportionate to the multiplication factor of the exchange rate
            // The reason for this is that the shares minted are inversely proportionate
            // to to the exchange rate
            // Therefore if exchange rate increases a lot the amount of shares minted will be less
            uint256 exchangeRateMultiplier = vaultExchangeRateAfter / vaultExchangeRateBefore;
            uint256 log10ExchangeRateMultiplier = MathUtils.log10(exchangeRateMultiplier) + 1;

            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                10 ** log10ExchangeRateMultiplier,
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
}
