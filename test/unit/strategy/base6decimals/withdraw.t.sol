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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockSwapper} from "test/unit/mocks/MockSwapper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {SetupBase6DecimalsBaseStrategy} from "test/unit/strategy/base6decimals/SetupBase6DecimalsBaseStrategy.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";

contract BaseStrategy6DecimalsBaseWithdrawalUnitTest is Test, MainnetActors, Etches {
    MockStrategy public vault;
    address public alice = address(0x12345);
    WrappedToken public wusdc;
    MockSwapper public swapper;
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;

    function setUp() public {
        SetupBase6DecimalsBaseStrategy setupVault = new SetupBase6DecimalsBaseStrategy();

        (vault,) = setupVault.setup();

        vm.prank(ADMIN);
        vault.setAlwaysComputeTotalAssets(false);

        wusdc = setupVault.wusdc();

        swapper = setupVault.swapper();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);

        // Set up approval rule for USDE to SUSDE
        vm.startPrank(PROCESSOR_MANAGER);
        // Create an allowlist with both SUSDE and swapper
        address[] memory allowList = new address[](2);
        allowList[0] = MC.SUSDE;
        allowList[1] = address(swapper);
        SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(MC.USDE, allowList);
        vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
        SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(MC.SUSDE, address(vault));
        vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);
        vm.stopPrank();
    }

    function test_Vault_withdrawUSDE_afterUSDCDeposit(uint256 usdcDepositAmount, uint256 usdeDepositAmount) public {
        vm.assume(usdcDepositAmount >= 1 && usdcDepositAmount <= 1_000_000e6); // Reasonable USDC amount (6 decimals)
        vm.assume(usdeDepositAmount >= 1 && usdeDepositAmount <= 1_000_000e18); // Reasonable USDE amount (18 decimals)

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDE using withdrawAsset
        vm.startPrank(alice);
        vault.withdrawAsset(MC.USDE, sharesMintedFromUSDE, alice, alice);
        vm.stopPrank();

        // Check that the vault sent back the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), 0, "Vault did not send back USDE");

        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), usdeDepositAmount, "Alice's USDE balance did not increase correctly");

        // Check that all shares from USDE deposit were burned
        assertEq(vault.balanceOf(alice), sharesMintedFromUSDC, "Alice's shares from USDE were not burned correctly");

        // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(vault.totalAssets(), usdcDepositAmount, "Total assets did not decrease correctly");

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_redeemUSDE_afterUSDCDeposit(uint256 usdcDepositAmount, uint256 usdeDepositAmount) public {
        vm.assume(usdcDepositAmount >= 1 && usdcDepositAmount <= 1_000_000e6); // Reasonable USDC amount (6 decimals)
        vm.assume(usdeDepositAmount >= 1 && usdeDepositAmount <= 1_000_000e18); // Reasonable USDE amount (18 decimals)

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Redeem USDE using redeemAsset
        vm.startPrank(alice);
        uint256 usdeReceived = vault.redeemAsset(MC.USDE, sharesMintedFromUSDE, alice, alice);
        vm.stopPrank();

        // Check that the vault sent back the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), 0, "Vault did not send back USDE");

        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), usdeReceived, "Alice's USDE balance did not increase correctly");

        // Check that all shares from USDE deposit were burned
        assertEq(vault.balanceOf(alice), sharesMintedFromUSDC, "Alice's shares from USDE were not burned correctly");

        // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(vault.totalAssets(), usdcDepositAmount, "Total assets did not decrease correctly");

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_withdrawUSDE_afterUSDCDeposit_WithFees(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1000, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1000, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDE using withdrawAsset
        uint256 assetsToWithdraw = usdeDepositAmount;
        vm.startPrank(alice);
        if (assetsToWithdraw > vault.maxWithdrawAsset(MC.USDE, alice)) {
            assetsToWithdraw = vault.maxWithdrawAsset(MC.USDE, alice);
        }
        uint256 shareBalanceBeforeWithdraw = vault.balanceOf(alice);
        uint256 redeemedAmount = vault.withdrawAsset(MC.USDE, assetsToWithdraw, alice, alice);
        uint256 expectedFee = (assetsToWithdraw * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDE, expectedFee);
        vm.stopPrank();

        assertEq(
            IERC20(MC.USDE).balanceOf(address(vault)),
            usdeDepositAmount - assetsToWithdraw,
            "Vault did not send back USDE"
        );

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqAbs(
            vault.previewDepositAsset(
                MC.USDE, vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient())
            ),
            expectedFee,
            5,
            "Performance fee recipient should have correct shares"
        );
        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), assetsToWithdraw, "Alice's USDE balance did not increase correctly");

        // // Check that all shares from USDE deposit were burned
        assertEq(
            vault.balanceOf(alice),
            shareBalanceBeforeWithdraw - redeemedAmount,
            "Alice's shares from USDE were not burned correctly"
        );

        // // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(
            vault.totalAssets(),
            usdcDepositAmount + (usdeDepositAmount - assetsToWithdraw) / 1e12,
            "Total assets did not decrease correctly"
        );

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12 + (usdeDepositAmount - assetsToWithdraw),
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_redeemUSDE_afterUSDCDeposit_WithFees(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1000, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1000, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDE using withdrawAsset
        uint256 amountToRedeem = sharesMintedFromUSDE;
        vm.startPrank(alice);
        if (amountToRedeem > vault.maxRedeemAsset(MC.USDE, alice)) {
            amountToRedeem = vault.maxRedeemAsset(MC.USDE, alice);
        }
        uint256 shareBalanceBeforeWithdraw = vault.balanceOf(alice);
        uint256 usdeReceived = vault.redeemAsset(MC.USDE, amountToRedeem, alice, alice);
        uint256 expectedFee = (usdeReceived * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDE, expectedFee);
        vm.stopPrank();

        assertEq(
            IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount - usdeReceived, "Vault did not send back USDE"
        );

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqAbs(
            vault.previewDepositAsset(
                MC.USDE, vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient())
            ),
            expectedFee,
            5,
            "Performance fee recipient should have correct shares"
        );
        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), usdeReceived, "Alice's USDE balance did not increase correctly");

        // // Check that all shares from USDE deposit were burned
        assertEq(
            vault.balanceOf(alice),
            shareBalanceBeforeWithdraw - amountToRedeem,
            "Alice's shares from USDE were not burned correctly"
        );

        // // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(
            vault.totalAssets(),
            usdcDepositAmount + (usdeDepositAmount - usdeReceived) / 1e12,
            "Total assets did not decrease correctly"
        );

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12 + (usdeDepositAmount - usdeReceived),
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_withdrawUSDE_afterUSDCDeposit_WithFeesOverride(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee,
        uint64 overrideWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1000, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1000, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideWithdrawalFee = uint64(bound(overrideWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);
        vault.overrideBaseWithdrawalFee(alice, overrideWithdrawalFee, true);
        vm.stopPrank();

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDE using withdrawAsset
        uint256 assetsToWithdraw = usdeDepositAmount;
        vm.startPrank(alice);
        if (assetsToWithdraw > vault.maxWithdrawAsset(MC.USDE, alice)) {
            assetsToWithdraw = vault.maxWithdrawAsset(MC.USDE, alice);
        }
        uint256 shareBalanceBeforeWithdraw = vault.balanceOf(alice);
        uint256 redeemedAmount = vault.withdrawAsset(MC.USDE, assetsToWithdraw, alice, alice);
        uint256 expectedFee = (assetsToWithdraw * overrideWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDE, expectedFee);
        vm.stopPrank();

        assertEq(
            IERC20(MC.USDE).balanceOf(address(vault)),
            usdeDepositAmount - assetsToWithdraw,
            "Vault did not send back USDE"
        );

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqAbs(
            vault.previewDepositAsset(
                MC.USDE, vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient())
            ),
            expectedFee,
            5,
            "Performance fee recipient should have correct shares"
        );
        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), assetsToWithdraw, "Alice's USDE balance did not increase correctly");

        // // Check that all shares from USDE deposit were burned
        assertEq(
            vault.balanceOf(alice),
            shareBalanceBeforeWithdraw - redeemedAmount,
            "Alice's shares from USDE were not burned correctly"
        );

        // // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(
            vault.totalAssets(),
            usdcDepositAmount + (usdeDepositAmount - assetsToWithdraw) / 1e12,
            "Total assets did not decrease correctly"
        );

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12 + (usdeDepositAmount - assetsToWithdraw),
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_redeemUSDE_afterUSDCDeposit_WithFeesOverride(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee,
        uint64 overrideWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1000, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1000, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideWithdrawalFee = uint64(bound(overrideWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);
        vault.overrideBaseWithdrawalFee(alice, overrideWithdrawalFee, true);
        vm.stopPrank();

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDE using withdrawAsset
        uint256 amountToRedeem = sharesMintedFromUSDE;
        vm.startPrank(alice);
        if (amountToRedeem > vault.maxRedeemAsset(MC.USDE, alice)) {
            amountToRedeem = vault.maxRedeemAsset(MC.USDE, alice);
        }
        uint256 shareBalanceBeforeWithdraw = vault.balanceOf(alice);
        uint256 usdeReceived = vault.redeemAsset(MC.USDE, amountToRedeem, alice, alice);
        uint256 expectedFee = (usdeReceived * overrideWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDE, expectedFee);
        vm.stopPrank();

        assertEq(
            IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount - usdeReceived, "Vault did not send back USDE"
        );

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            5,
            "Performance fee recipient should have correct shares"
        );
        assertApproxEqAbs(
            vault.previewDepositAsset(
                MC.USDE, vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient())
            ),
            expectedFee,
            5,
            "Performance fee recipient should have correct shares"
        );
        // Check that Alice's USDE balance increased
        assertEq(IERC20(MC.USDE).balanceOf(alice), usdeReceived, "Alice's USDE balance did not increase correctly");

        // // Check that all shares from USDE deposit were burned
        assertEq(
            vault.balanceOf(alice),
            shareBalanceBeforeWithdraw - amountToRedeem,
            "Alice's shares from USDE were not burned correctly"
        );

        // // Check that total assets decreased by the USD value of USDE (usdeDepositAmount / 1e12)
        assertEq(
            vault.totalAssets(),
            usdcDepositAmount + (usdeDepositAmount - usdeReceived) / 1e12,
            "Total assets did not decrease correctly"
        );

        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdcDepositAmount * 1e12 + (usdeDepositAmount - usdeReceived),
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_withdrawUSDC_afterUSDEDeposit(uint256 usdcDepositAmount, uint256 usdeDepositAmount) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1, 1_000_000e18);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDC using withdrawAsset
        vm.startPrank(alice);
        vault.withdrawAsset(MC.USDC, sharesMintedFromUSDC / 1e12, alice, alice);
        vm.stopPrank();

        // Check that the vault sent back the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault did not send back USDC");

        // Check that Alice's USDC balance increased
        assertEq(IERC20(MC.USDC).balanceOf(alice), usdcDepositAmount, "Alice's USDC balance did not increase correctly");

        // Check that all shares from USDC deposit were burned
        assertEq(vault.balanceOf(alice), sharesMintedFromUSDE, "Alice's shares from USDC were not burned correctly");

        // Check that total assets decreased by the USD value of USDC
        assertEq(vault.totalAssets(), usdeDepositAmount / 1e12, "Total assets did not decrease correctly");
        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_redeemUSDC_afterUSDEDeposit(uint256 usdcDepositAmount, uint256 usdeDepositAmount) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1, 1_000_000e18);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Withdraw USDC using withdrawAsset
        vm.startPrank(alice);
        uint256 usdcReceived = vault.redeemAsset(MC.USDC, sharesMintedFromUSDC, alice, alice);
        vm.stopPrank();

        // Check that the vault sent back the USDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount - usdcReceived, "Vault did not send back USDC"
        );

        // Check that Alice's USDC balance increased
        assertEq(IERC20(MC.USDC).balanceOf(alice), usdcReceived, "Alice's USDC balance did not increase correctly");

        // Check that all shares from USDC deposit were burned
        assertEq(vault.balanceOf(alice), sharesMintedFromUSDE, "Alice's shares from USDC were not burned correctly");

        // Check that total assets decreased by the USD value of USDC
        assertEq(vault.totalAssets(), usdeDepositAmount / 1e12, "Total assets did not decrease correctly");
        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_withdrawUSDC_afterUSDEDepositWithFees(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        uint256 assetsToWithdraw = usdcDepositAmount;
        if (assetsToWithdraw > vault.maxWithdrawAsset(MC.USDC, alice)) {
            assetsToWithdraw = vault.maxWithdrawAsset(MC.USDC, alice);
        }

        // Withdraw USDC using withdrawAsset
        vm.startPrank(alice);
        uint256 sharesBurned = vault.withdrawAsset(MC.USDC, assetsToWithdraw, alice, alice);
        uint256 expectedFee = (assetsToWithdraw * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDC, expectedFee);
        uint256 expectedSharesBurned = vault.previewDepositAsset(MC.USDC, assetsToWithdraw + expectedFee);
        vm.stopPrank();

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            1e14,
            "Performance fee recipient should have correct shares"
        );

        assertApproxEqAbs(
            sharesBurned, expectedSharesBurned, 1e14, "Shares burned should be equivalent to expected shares"
        );

        // Check that the vault sent back the USDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            usdcDepositAmount - assetsToWithdraw,
            "Vault did not send back USDC"
        );

        // Check that Alice's USDC balance increased
        assertEq(IERC20(MC.USDC).balanceOf(alice), assetsToWithdraw, "Alice's USDC balance did not increase correctly");

        // Check that all shares from USDC deposit were burned
        assertEq(
            vault.balanceOf(alice),
            sharesMintedFromUSDE + sharesMintedFromUSDC - sharesBurned,
            "Alice's shares from USDC were not burned correctly"
        );

        // Check that total assets decreased by the USD value of USDC
        assertEq(
            vault.totalAssets(),
            usdeDepositAmount / 1e12 + (usdcDepositAmount - assetsToWithdraw),
            "Total assets did not decrease correctly"
        );
        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount + (usdcDepositAmount - assetsToWithdraw) * 1e12,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_redeemUSDC_afterUSDEDepositWithFees(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        uint256 amountToRedeem = sharesMintedFromUSDC;
        if (amountToRedeem > vault.maxRedeemAsset(MC.USDC, alice)) {
            amountToRedeem = vault.maxRedeemAsset(MC.USDC, alice);
        }

        // Withdraw USDC using withdrawAsset
        vm.startPrank(alice);
        uint256 usdcReceived = vault.redeemAsset(MC.USDC, amountToRedeem, alice, alice);
        uint256 expectedFee = (usdcReceived * baseWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDC, expectedFee);
        vm.stopPrank();

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            1e14,
            "Performance fee recipient should have correct shares"
        );

        // Check that the vault sent back the USDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount - usdcReceived, "Vault did not send back USDC"
        );

        // Check that Alice's USDC balance increased
        assertEq(IERC20(MC.USDC).balanceOf(alice), usdcReceived, "Alice's USDC balance did not increase correctly");

        // Check that all shares from USDC deposit were burned
        assertEq(vault.balanceOf(alice), sharesMintedFromUSDE, "Alice's shares from USDC were not burned correctly");

        // Check that total assets decreased by the USD value of USDC
        assertEq(
            vault.totalAssets(),
            usdeDepositAmount / 1e12 + (usdcDepositAmount - usdcReceived),
            "Total assets did not decrease correctly"
        );
        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount + (usdcDepositAmount - usdcReceived) * 1e12,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function test_Vault_withdrawUSDC_afterUSDEDepositWithOverrideFees(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint64 baseWithdrawalFee,
        uint64 overrideWithdrawalFee
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1, 1_000_000e6);
        usdeDepositAmount = bound(usdeDepositAmount, 1, 1_000_000e18);
        baseWithdrawalFee = uint64(bound(baseWithdrawalFee, 100, FeeMath.BASIS_POINT_SCALE));
        overrideWithdrawalFee = uint64(bound(overrideWithdrawalFee, 0, FeeMath.BASIS_POINT_SCALE));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(baseWithdrawalFee);
        vault.overrideBaseWithdrawalFee(alice, overrideWithdrawalFee, true);
        vm.stopPrank();

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), usdcDepositAmount, "Vault did not receive USDC");

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        vm.startPrank(alice);
        uint256 assetsToWithdraw = usdcDepositAmount;
        if (assetsToWithdraw > vault.maxWithdrawAsset(MC.USDC, alice)) {
            assetsToWithdraw = vault.maxWithdrawAsset(MC.USDC, alice);
        }

        // Withdraw USDC using withdrawAsset
        uint256 sharesBurned = vault.withdrawAsset(MC.USDC, assetsToWithdraw, alice, alice);
        uint256 expectedFee = (assetsToWithdraw * overrideWithdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 feeShares = vault.previewDepositAsset(MC.USDC, expectedFee);
        uint256 expectedSharesBurned = vault.previewDepositAsset(MC.USDC, assetsToWithdraw + expectedFee);
        vm.stopPrank();

        assertApproxEqAbs(
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient()),
            feeShares,
            1e14,
            "Performance fee recipient should have correct shares"
        );

        assertApproxEqAbs(
            sharesBurned, expectedSharesBurned, 1e14, "Shares burned should be equivalent to expected shares"
        );

        // Check that the vault sent back the USDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            usdcDepositAmount - assetsToWithdraw,
            "Vault did not send back USDC"
        );

        // Check that Alice's USDC balance increased
        assertEq(IERC20(MC.USDC).balanceOf(alice), assetsToWithdraw, "Alice's USDC balance did not increase correctly");

        // Check that all shares from USDC deposit were burned
        assertEq(
            vault.balanceOf(alice),
            sharesMintedFromUSDE + sharesMintedFromUSDC - sharesBurned,
            "Alice's shares from USDC were not burned correctly"
        );

        // Check that total assets decreased by the USD value of USDC
        assertEq(
            vault.totalAssets(),
            usdeDepositAmount / 1e12 + (usdcDepositAmount - assetsToWithdraw),
            "Total assets did not decrease correctly"
        );
        // Check that the total base assets in the vault match the expected value
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount + (usdcDepositAmount - assetsToWithdraw) * 1e12,
            "Total base assets did not match expected value after withdrawal"
        );
    }
}
