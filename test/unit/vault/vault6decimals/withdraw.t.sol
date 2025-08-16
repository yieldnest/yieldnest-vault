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
import {Setup6DecimalsVault} from "test/unit/vault/vault6decimals/Setup6DecimalsVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Hooks} from "src/module/Hooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {FeeMath} from "src/module/FeeMath.sol";

contract Vault6DecimalsWithdrawUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = makeAddr("alice");
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;
    Hooks public hooks;

    function setUp() public {
        Setup6DecimalsVault setupVault = new Setup6DecimalsVault();
        (vault,) = setupVault.setup();
        hooks = Hooks(address(vault.hooks()));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function allocateToBuffer(uint256 amount) internal {
        // Allocate the specified amount to the buffer
        // First approve USDC to the buffer
        uint256 usdcBalanceBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 bufferSharesBefore = IERC20(MC.BUFFER).balanceOf(address(vault));

        address[] memory targets = new address[](2);
        targets[0] = MC.USDC;
        targets[1] = MC.BUFFER;

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, MC.BUFFER, amount);
        calldatas[1] = abi.encodeWithSelector(IERC4626.deposit.selector, amount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, new uint256[](2), calldatas);

        // Verify the buffer deposit was successful
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            usdcBalanceBefore - amount,
            "Vault USDC balance should decrease by the deposited amount"
        );
        assertEq(
            IERC20(MC.BUFFER).balanceOf(address(vault)),
            bufferSharesBefore + amount,
            "Vault buffer shares should increase by the deposited amount"
        );
        assertEq(IERC20(MC.BUFFER).balanceOf(address(vault)), amount, "Vault should have received buffer shares");
    }

    function test_depositAndWithdrawWUSDC_without_fees(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, 1_000_000 * 1e6);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before withdrawal
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before withdrawal
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        // Calculate shares to burn for withdrawal
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);

        // Withdraw USDC from the vault
        vm.startPrank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Verify withdrawal was successful
        assertEq(
            vault.balanceOf(alice), sharesReceived - sharesToBurn, "Alice's shares should be reduced by burned amount"
        );
        assertEq(vault.totalSupply(), sharesReceived - sharesToBurn, "Total supply should be reduced by burned amount");
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore - withdrawAmount,
            "Buffer's USDC balance should be reduced by withdrawn amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - withdrawAmount;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by withdraw amount");
    }

    function test_depositAndWithdrawWUSDC_with_fees(uint256 depositAmount, uint256 withdrawAmount, uint64 withdrawalFee)
        public
    {
        withdrawalFee = uint64(bound(withdrawalFee, 1, FeeMath.BASIS_POINT_SCALE / 2));

        depositAmount = bound(depositAmount, 1e6, 100_000 * 1e6);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before withdrawal
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before withdrawal
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        if (withdrawAmount > vault.maxWithdraw(alice)) {
            withdrawAmount = vault.maxWithdraw(alice);
        }

        uint256 expectedFee = (withdrawAmount * withdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        // Calculate shares to burn for withdrawal
        uint256 sharesToBurn = vault.convertToShares(withdrawAmount + expectedFee);

        // Withdraw USDC from the vault
        vm.startPrank(alice);
        uint256 totalSharesOfPerformanceFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);
        uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesMintedToPerformanceFeeRecipient =
            totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
        assertApproxEqAbs(sharesBurned, sharesToBurn, 1e3, "correct shares should be burned");
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient), expectedFee, 5, "correct fee should be minted"
        );
        assertApproxEqAbs(vault.convertToAssets(1e6), assetsPerShareBefore, 5, "correct asset per share ratio");
        vm.stopPrank();

        // Verify withdrawal was successful
        assertEq(
            vault.balanceOf(alice), sharesReceived - sharesBurned, "Alice's shares should be reduced by burned amount"
        );
        assertEq(
            vault.totalSupply(),
            sharesReceived - sharesBurned + sharesMintedToPerformanceFeeRecipient,
            "Total supply should be reduced by burned amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore - withdrawAmount,
            "Buffer's USDC balance should be reduced by withdrawn amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - withdrawAmount;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by withdraw amount");
    }

    function test_depositAndWithdrawWUSDC_with_full_fees(uint256 depositAmount, uint256 withdrawAmount) public {
        uint64 withdrawalFee = uint64(FeeMath.BASIS_POINT_SCALE);
        depositAmount = bound(depositAmount, 5, 1_000_000 * 1e6);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before withdrawal
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before withdrawal
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        if (withdrawAmount > vault.maxWithdraw(alice)) {
            withdrawAmount = vault.maxWithdraw(alice);
        }

        uint256 expectedFee = (withdrawAmount * withdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        assertEq(expectedFee, withdrawAmount, "incorrect expected fee");
        uint256 sharesToBurn = vault.convertToShares(withdrawAmount + expectedFee);

        // Withdraw USDC from the vault
        vm.startPrank(alice);
        uint256 totalSharesOfPerformanceFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);
        uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesMintedToPerformanceFeeRecipient =
            totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
        assertApproxEqAbs(sharesBurned, sharesToBurn, 1e3, "correct shares should be burned");
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient), expectedFee, 5, "correct fee should be minted"
        );
        assertApproxEqAbs(vault.convertToAssets(1e6), assetsPerShareBefore, 5, "correct asset per share ratio");
        vm.stopPrank();

        // Verify withdrawal was successful
        assertEq(
            vault.totalSupply(),
            sharesReceived - sharesBurned + sharesMintedToPerformanceFeeRecipient,
            "Total supply should be reduced by burned amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore - withdrawAmount,
            "Buffer's USDC balance should be reduced by withdrawn amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - withdrawAmount;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by withdraw amount");
    }

    function test_Vault_deposit_usdc_and_redeem_usdc_success_without_fees(uint256 depositAmount, uint256 redeemShares)
        public
    {
        depositAmount = bound(depositAmount, 1, 1_000_000 * 1e6);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();

        // Bound redeem shares to be less than or equal to shares received
        redeemShares = bound(redeemShares, 1, sharesReceived);

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before redemption
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before redemption
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        // Calculate expected assets to receive
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        // Redeem shares from the vault
        vm.startPrank(alice);
        uint256 assetsReceived = vault.redeem(redeemShares, alice, alice);
        vm.stopPrank();

        // Verify redemption was successful
        assertEq(assetsReceived, expectedAssets, "Assets received should match preview");
        assertEq(
            vault.balanceOf(alice), sharesReceived - redeemShares, "Alice's shares should be reduced by redeemed amount"
        );
        assertEq(
            vault.totalSupply(), sharesReceived - redeemShares, "Total supply should be reduced by redeemed amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), expectedAssets, "Alice should have received the expected assets");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore - expectedAssets,
            "Buffer's USDC balance should be reduced by redeemed amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after redemption"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - expectedAssets;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by redeemed amount");
    }

    function test_Vault_deposit_usdc_and_redeem_usdc_success_with_fees(
        uint256 depositAmount,
        uint256 redeemShares,
        uint64 withdrawalFee
    ) public {
        withdrawalFee = uint64(bound(withdrawalFee, 1, FeeMath.BASIS_POINT_SCALE / 2));

        depositAmount = bound(depositAmount, 1e6, 100_000 * 1e6);
        redeemShares = bound(redeemShares, 1, depositAmount);

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();

        // Bound redeem shares to be less than or equal to shares received
        redeemShares = bound(redeemShares, 1, sharesReceived);

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before redemption
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before redemption
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        // Calculate expected assets to receive
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        // Redeem shares from the vault
        vm.startPrank(alice);
        uint256 totalSharesOfPerformanceFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 assetsReceived = vault.redeem(redeemShares, alice, alice);
        uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 expectedFee = (assetsReceived * withdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        uint256 sharesMintedToPerformanceFeeRecipient =
            totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient), expectedFee, 5, "correct fee should be minted"
        );
        vm.stopPrank();

        // Verify redemption was successful
        assertEq(assetsReceived, expectedAssets, "Assets received should match preview");
        assertEq(
            vault.balanceOf(alice), sharesReceived - redeemShares, "Alice's shares should be reduced by redeemed amount"
        );
        assertEq(
            vault.totalSupply(),
            sharesReceived - redeemShares + sharesMintedToPerformanceFeeRecipient,
            "Total supply should be reduced by redeemed amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), expectedAssets, "Alice should have received the expected assets");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore - expectedAssets,
            "Buffer's USDC balance should be reduced by redeemed amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after redemption"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - expectedAssets;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by redeemed amount");
    }

    function test_Vault_deposit_usdc_and_redeem_usdc_success_with_full_fees(uint256 depositAmount, uint256 redeemShares)
        public
    {
        uint64 withdrawalFee = uint64(FeeMath.BASIS_POINT_SCALE);

        depositAmount = bound(depositAmount, 1e6, 1_000_000 * 1e6);

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        // Give Alice USDC
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC into the vault
        uint256 sharesReceived = vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();

        // Bound redeem shares to be less than or equal to shares received
        redeemShares = bound(redeemShares, 1, sharesReceived);

        if (redeemShares > vault.maxRedeem(alice)) {
            redeemShares = vault.maxRedeem(alice);
        }

        // Verify deposit was successful
        assertEq(vault.balanceOf(alice), sharesReceived, "Alice should have received shares");
        assertEq(vault.totalSupply(), sharesReceived, "Total supply should match shares received");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC balance should be 0 after deposit");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault should have received the USDC");

        // Record state before redemption
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsPerShareBefore = vault.convertToAssets(1e6);

        allocateToBuffer(depositAmount);

        // Record buffer's USDC balance before redemption
        uint256 bufferUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(address(MC.BUFFER));

        // Calculate expected assets to receive
        uint256 expectedAssets = vault.previewRedeem(redeemShares);
        assertEq(expectedAssets, 0, "incorrect expected assets");

        // Redeem shares from the vault
        vm.startPrank(alice);
        uint256 totalSharesOfPerformanceFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 assetsReceived = vault.redeem(redeemShares, alice, alice);
        uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesMintedToPerformanceFeeRecipient =
            totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient),
            assetsReceived,
            5,
            "correct fee should be minted"
        );
        assertApproxEqAbs(sharesMintedToPerformanceFeeRecipient, redeemShares, 5, "incorrect shares received");
        vm.stopPrank();

        // Verify redemption was successful
        assertEq(assetsReceived, 0, "Assets received should match preview");
        assertEq(
            vault.balanceOf(alice), sharesReceived - redeemShares, "Alice's shares should be reduced by redeemed amount"
        );
        assertEq(
            vault.totalSupply(),
            sharesReceived - redeemShares + sharesMintedToPerformanceFeeRecipient,
            "Total supply should be reduced by redeemed amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice should have received the expected assets");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(MC.BUFFER)),
            bufferUSDCBalanceBefore,
            "Buffer's USDC balance should be reduced by redeemed amount"
        );

        // Check asset per share ratio
        uint256 assetsPerShareAfter = vault.convertToAssets(1e6);
        assertApproxEqAbs(assetsPerShareAfter, assetsPerShareBefore, 5, "Asset per share ratio should remain same");

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by redeemed amount");
    }
}
