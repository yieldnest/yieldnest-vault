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
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {SetupBase6DecimalsVault} from "test/unit/vault/base6decimals/SetupBase6DecimalsVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {MathUtils} from "test/utils/MathUtils.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";

contract Vault6DecimalsBaseHooksUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;
    FeeHooks public hooks;

    WrappedToken public wusdc;

    function setUp() public {
        SetupBase6DecimalsVault setupVault = new SetupBase6DecimalsVault();
        (vault,) = setupVault.setup();
        wusdc = setupVault.wusdc();
        hooks = FeeHooks(address(vault.hooks()));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function test_ProcessAccounting_Basic() public {
        uint256 depositAmount = 1000e6; // 1000 USDC (6 decimals)
        uint256 yield = 100e6; // 100 USDC yield
        uint256 performanceFee = 10e6; // 10 USDC performance fee (10% of yield)

        // Give alice USDC tokens
        deal(MC.USDC, alice, depositAmount + yield);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        vault.processAccounting();

        // Vault has 6 decimals, so shares should be scaled by 1e12 (18-6)
        assertEq(vault.totalSupply(), depositAmount * 1e12, "vault's total supply should be depositAmount * 1e12");
        assertEq(vault.totalAssets(), depositAmount, "vault's total assets should be depositAmount");

        // alice transfers yield to vault
        vm.prank(alice);
        IERC20(MC.USDC).transfer(address(vault), yield);

        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        vault.processAccounting();

        uint256 performanceFeeRecipientSharesAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 performanceFeeSharesReceived = performanceFeeRecipientSharesAfter - performanceFeeRecipientSharesBefore;

        assertLe(
            vault.convertToAssets(performanceFeeSharesReceived),
            performanceFee,
            "performance fee shares received should be less than or equal to performance fee"
        );
        assertApproxEqAbs(
            vault.convertToAssets(performanceFeeSharesReceived),
            performanceFee,
            2,
            "performance fee shares received should be equal to performance fee"
        );
        assertEq(
            vault.totalSupply(),
            shares + performanceFeeSharesReceived,
            "vault's total supply should be equal to shares + performance fee shares received"
        );
        assertEq(
            vault.totalAssets(), depositAmount + yield, "vault's total assets should be equal to depositAmount + yield"
        );
    }

    function test_ProcessAccounting_100_Percent_Performance_Fee_With_100_Percent_Yield() public {
        uint256 rateBefore = vault.convertToAssets(1e18);

        processAccounting_100_Percent_Performance_Fee(1000e6, 1000e6);

        uint256 rateAfter = vault.convertToAssets(1e18);
        assertEq(rateBefore, 1e6, "rate before should be 1e6");
        assertEq(rateAfter, 1e6, "rate after should be 1e6");

        assertEq(vault.totalAssets(), 2000e6, "vault's total assets should be 2000e6");
        assertEq(vault.totalSupply(), 2000e18, "vault's total supply should be 2e18");
    }

    function test_Fuzz_ProcessAccounting_100_Percent_Performance_Fee(uint256 depositAmount, uint256 yield) public {
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);
        yield = bound(yield, 0, depositAmount * 10);
        processAccounting_100_Percent_Performance_Fee(depositAmount, yield);
    }

    function processAccounting_100_Percent_Performance_Fee(uint256 depositAmount, uint256 yield) public {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(1 ether); // 100% performance fee
        vm.stopPrank();

        deal(MC.USDC, alice, depositAmount);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        vault.processAccounting();

        assertEq(vault.totalSupply(), depositAmount * 1e12, "vault's total supply should be depositAmount * 1e12");
        assertEq(vault.totalAssets(), depositAmount, "vault's total assets should be depositAmount");
        assertEq(shares, depositAmount * 1e12, "shares should be depositAmount * 1e12");

        deal(MC.USDC, address(this), yield);

        IERC20(MC.USDC).transfer(address(vault), yield);
        uint256 performanceFeeRecipientSharesBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        uint256 convertToAssetsBefore = vault.convertToAssets(1e18);
        assertEq(convertToAssetsBefore, 1e6, "vault's convertToAssets should be 1e6");

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
                depositAmount * 1e12 + performanceFeeSharesReceived,
                "vault's total supply should include fee shares"
            );
            assertEq(vault.totalAssets(), depositAmount + yield, "vault's total assets should be depositAmount + yield");

            // Alice's share value should remain the same (depositAmount worth of assets)
            uint256 aliceAssetValue = vault.convertToAssets(vault.balanceOf(alice));
            assertEq(aliceAssetValue, depositAmount, "Alice's asset value should remain depositAmount");
        } else {
            // With no yield, no performance fee should be collected
            assertEq(performanceFeeSharesReceived, 0, "performance fee shares received should be 0 with no yield");
            assertEq(
                vault.totalSupply(), depositAmount * 1e12, "vault's total supply should remain depositAmount * 1e12"
            );
            assertEq(vault.totalAssets(), depositAmount, "vault's total assets should remain depositAmount");
        }
    }

    function test_AfterProcessAccounting_Invariants(uint256 totalAssetsBefore, uint256 totalAssetsAfter) public {
        totalAssetsBefore = bound(totalAssetsBefore, 1 * 10 ** 6, 1_000_000 * 10 ** 6);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 100 * 10 ** 6, 1_000_101 * 10 ** 6);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 6);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        donationAmount = donationAmount;
        deal((MC.USDC), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.USDC).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.USDC).transfer(address(vault), donationAmount);
        vm.stopPrank();

        vm.startPrank(address(vault));
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
        uint256 feesAccrued = (donationAmount * hooks.performanceFee()) / 1 ether;
        vm.stopPrank();

        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        if (feesAccrued > 0) {
            uint256 performanceFeeShares = vaultTotalSupplyAfter - vaultTotalSupplyBefore;

            assertLe(
                vault.convertToAssets(performanceFeeShares),
                feesAccrued,
                "performance fee shares should be less than or equal to performance fee amount"
            );

            if (vaultExchangeRateAfter < 3e6) {
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
            assertGt(
                vaultTotalSupplyAfter,
                vaultTotalSupplyBefore,
                "vault's total supply should increase due to fee shares minted"
            );
            assertGt(
                vaultTotalAssetsAfter,
                vaultTotalAssetsBefore,
                "vault's total assets should increase due to fee shares minted"
            );
            assertGt(
                vaultExchangeRateAfter,
                vaultExchangeRateBefore,
                "vault's exchange rate should always increase due to donation"
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

        vm.stopPrank();
    }

    function test_AfterProcessingAccountWithNoPerformanceFee(uint256 totalAssetsBefore, uint256 totalAssetsAfter)
        public
    {
        vm.startPrank(ADMIN);
        hooks.setPerformanceFee(0);
        vm.stopPrank();

        totalAssetsBefore = bound(totalAssetsBefore, 1 * 10 ** 6, 1_000_000 * 10 ** 6);
        totalAssetsAfter = bound(totalAssetsAfter, totalAssetsBefore + 100 * 10 ** 6, 1_000_101 * 10 ** 6);

        assertEq(vault.decimals(), 18);
        address vaultAsset = vault.asset();
        uint256 vaultAssetDecimals = ERC20(vaultAsset).decimals();
        assertEq(vaultAssetDecimals, 6);
        address user1 = makeAddr("user1");

        uint256 donationAmount = totalAssetsAfter - totalAssetsBefore;
        donationAmount = donationAmount;
        deal((MC.USDC), user1, totalAssetsBefore + donationAmount);

        vm.startPrank(user1);
        IERC20(MC.USDC).approve(address(vault), totalAssetsBefore);
        vault.deposit(totalAssetsBefore, user1);
        vault.processAccounting();

        IERC20(MC.USDC).transfer(address(vault), donationAmount);
        vm.stopPrank();

        vm.startPrank(address(vault));
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        uint256 vaultExchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());

        hooks.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBefore,
                totalAssetsAfterAccounting: totalAssetsAfter,
                totalSupplyBeforeAccounting: vaultTotalSupplyBefore,
                totalSupplyAfterAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether,
                totalBaseAssetsAfterAccounting: 1 ether
            })
        );
        vm.stopPrank();
        vault.processAccounting();

        uint256 vaultTotalSupplyAfter = vault.totalSupply();
        uint256 vaultExchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        assertEq(vaultTotalSupplyAfter, vaultTotalSupplyBefore, "vault's total supply should not change due to no fee");
        assertGt(
            vaultExchangeRateAfter,
            vaultExchangeRateBefore,
            "vault's exchange rate should always increase due to donation"
        );
        assertGt(
            vaultTotalAssetsAfter, vaultTotalAssetsBefore, "vault's total assets should always increase due to donation"
        );
        vm.stopPrank();
    }
}
