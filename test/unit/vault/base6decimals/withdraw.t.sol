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
import {FeeMath} from "src/module/FeeMath.sol";

contract Vault6DecimalsBaseWithdrawUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    WrappedToken public wusdc;

    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;
    MockSwapper public swapper;

    function setUp() public {
        SetupBase6DecimalsVault setupVault = new SetupBase6DecimalsVault();
        (vault,) = setupVault.setup();

        wusdc = setupVault.wusdc();

        swapper = setupVault.swapper();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function swapAndAllocateToBuffer(uint256 depositAmount) internal returns (uint256) {
        // Calculate how much USDC we expect to receive for our USDE
        uint256 expectedUsdcAmount = swapper.previewSwap(MC.USDE, MC.USDC, depositAmount);
        // Verify the expected USDC amount is depositAmount / 12
        assertEq(expectedUsdcAmount, depositAmount / 1e12, "Expected USDC amount should be depositAmount / 1e12");

        uint256 depositableAmount = depositAmount / 1e12 * 1e12;

        // Prepare the calldata for the swap function
        bytes memory swapCalldata =
            abi.encodeWithSelector(MockSwapper.swap.selector, MC.USDE, MC.USDC, depositableAmount);

        // First approve USDE to the swapper, then execute the swap
        address[] memory targets = new address[](2);
        targets[0] = address(MC.USDE);
        targets[1] = address(swapper);

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, address(swapper), depositableAmount);
        calldatas[1] = swapCalldata;
        // Get the initial USDC balance before the swap
        uint256 initialUsdcBalance = IERC20(MC.USDC).balanceOf(address(vault));

        vm.prank(PROCESSOR);
        bytes[] memory returnData = vault.processor(targets, new uint256[](2), calldatas);
        uint256 receivedUsdc = abi.decode(returnData[1], (uint256));

        // Verify the swap was successful
        assertEq(receivedUsdc, expectedUsdcAmount, "Received USDC should match expected amount");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            initialUsdcBalance + receivedUsdc,
            "Vault should have received the USDC"
        );

        // Allocate the received USDC to the buffer
        // First approve USDC to the buffer
        targets = new address[](2);
        targets[0] = address(MC.USDC);
        targets[1] = MC.BUFFER;

        calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, MC.BUFFER, receivedUsdc);
        calldatas[1] = abi.encodeWithSelector(IERC4626.deposit.selector, receivedUsdc, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, new uint256[](2), calldatas);

        // Verify the buffer deposit was successful
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            initialUsdcBalance,
            "Vault should have deposited converted USDC to buffer"
        );
        assertEq(IERC20(MC.BUFFER).balanceOf(address(vault)), receivedUsdc, "Vault should have received buffer shares");
        return receivedUsdc;
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

    function test_Vault_deposit_usde_and_withdraw_usdc_success_without_fees(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        vm.assume(depositAmount >= 1e12); // enough decimal points to be non-zero in USDC
        vm.assume(depositAmount <= 100_000 * 1e18);

        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount);
        withdrawAmount = withdrawAmount / 1e12; // USDC amount

        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        uint256 expectedTotalAssets = depositAmount;
        // total assets are in USDC
        assertEq(vault.totalBaseAssets(), expectedTotalAssets, "Total base assets should match deposit amount");
        assertEq(vault.totalAssets(), expectedTotalAssets / 1e12, "Total assets should match deposit amount");

        swapAndAllocateToBuffer(depositAmount);

        // Calculate expected shares to burn
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);
        // Check convertToAssets before withdrawal
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

        // Withdraw assets from the vault
        vm.startPrank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Check convertToAssets after withdrawal
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);

        // Assert that the conversion rate is greater than or equal after withdrawal
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );

        // Assert that the conversion rate remains approximately the same
        if (depositAmount >= 1e18) {
            assertApproxEqAbs(
                assetsPerShareBefore, assetsPerShareAfter, 1, "Asset per share ratio should remain constant"
            );
        } else {
            // TODO: fix the error margin here
            // more error at lower amounts
            assertApproxEqAbs(
                assetsPerShareBefore,
                assetsPerShareAfter,
                10 ** IERC20Metadata(MC.USDC).decimals(),
                "Asset per share ratio should remain constant"
            );
        }

        // Verify withdraw was successful
        assertEq(
            vault.balanceOf(alice), sharesReceived - sharesToBurn, "Alice's shares should be reduced by burned amount"
        );
        assertEq(vault.totalSupply(), sharesReceived - sharesToBurn, "Total supply should be reduced by burned amount");

        // Verify totalBaseAssets is reduced by the withdraw amount * 1e12 (to account for decimal conversion)
        assertApproxEqAbs(
            vault.totalBaseAssets(),
            expectedTotalAssets - withdrawAmount * 1e12,
            2,
            "Total base assets should be reduced by withdraw amount (in base units)"
        );
        assertEq(
            vault.totalAssets(),
            expectedTotalAssets / 1e12 - withdrawAmount,
            "Total assets should be reduced by withdraw amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn assets");
    }

    function test_Vault_deposit_usde_and_withdraw_usdc_success_with_fees(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint64 withdrawalFee
    ) public {
        depositAmount = bound(depositAmount, 1e12, 100_000 * 1e18);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        withdrawAmount = withdrawAmount / 1e12; // USDC amount
        withdrawalFee = uint64(bound(withdrawalFee, 1, FeeMath.BASIS_POINT_SCALE / 2));

        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        {
            uint256 maxWithdraw = vault.maxWithdraw(alice);
            if (withdrawAmount > maxWithdraw) {
                withdrawAmount = maxWithdraw;
            }
        }

        uint256 expectedTotalAssets = depositAmount;
        // total assets are in USDC
        assertEq(vault.totalBaseAssets(), expectedTotalAssets, "Total base assets should match deposit amount");
        assertEq(vault.totalAssets(), expectedTotalAssets / 1e12, "Total assets should match deposit amount");

        swapAndAllocateToBuffer(depositAmount);

        uint256 expectedFee = (withdrawAmount * withdrawalFee) / FeeMath.BASIS_POINT_SCALE;
        // Calculate expected shares to burn
        uint256 expectedSharesToBurn = vault.previewWithdraw(withdrawAmount + expectedFee);
        // Check convertToAssets before withdrawal
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

        // Withdraw assets from the vault
        vm.startPrank(alice);
        uint256 totalSharesOfPerformanceFeeRecipientBefore = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);
        uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
        vm.stopPrank();

        uint256 sharesMintedToPerformanceFeeRecipient =
            totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
        assertApproxEqAbs(sharesBurned, expectedSharesToBurn, 5, "correct shares should be burned");
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient), expectedFee, 5, "correct fee should be minted"
        );
        // Check convertToAssets after withdrawal
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);

        // Assert that the conversion rate remains approximately the same
        if (depositAmount >= 1e18) {
            assertApproxEqAbs(
                assetsPerShareBefore, assetsPerShareAfter, 1, "Asset per share ratio should remain constant"
            );
        } else {
            assertApproxEqAbs(
                assetsPerShareBefore, assetsPerShareAfter, 100, "Asset per share ratio should remain constant"
            );
        }

        // Verify withdraw was successful
        assertEq(
            vault.balanceOf(alice), sharesReceived - sharesBurned, "Alice's shares should be reduced by burned amount"
        );
        assertEq(
            vault.totalSupply(),
            sharesReceived - sharesBurned + sharesMintedToPerformanceFeeRecipient,
            "Total supply should be reduced by burned amount"
        );

        // Verify totalBaseAssets is reduced by the withdraw amount * 1e12 (to account for decimal conversion)
        assertApproxEqAbs(
            vault.totalBaseAssets(),
            expectedTotalAssets - withdrawAmount * 1e12,
            2,
            "Total base assets should be reduced by withdraw amount (in base units)"
        );
        assertEq(
            vault.totalAssets(),
            expectedTotalAssets / 1e12 - withdrawAmount,
            "Total assets should be reduced by withdraw amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn assets");
    }

    function test_Vault_deposit_usde_and_redeem_usdc_success_without_fees(uint256 depositAmount, uint256 withdrawAmount)
        public
    {
        vm.assume(depositAmount >= 1e12); // enough decimal points to be non-zero in USDC
        vm.assume(depositAmount <= 100_000 * 1e18);

        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount / 1e12);

        // Pre-deposit 1 million USDC to the vault
        uint256 preDepositAmount = 1_000_000 * 1e6; // 1 million USDC (6 decimals)
        {
            // Create a depositor account
            address depositor = address(0xDEAD);

            // Give the depositor USDC
            deal(MC.USDC, depositor, preDepositAmount);

            // Deposit USDC to the vault
            vm.startPrank(depositor);
            IERC20(MC.USDC).approve(address(vault), preDepositAmount);
            vault.depositAsset(MC.USDC, preDepositAmount, depositor);
            vm.stopPrank();
        }

        uint256 initialSupply = vault.totalSupply();

        // Bound withdraw amount to be less than or equal to deposit amount

        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        uint256 assetsPerShareBeforeDeposit = vault.convertToAssets(1e18);

        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        uint256 expectedTotalAssets = depositAmount + preDepositAmount * 1e12;
        // total assets are in WUSDC
        assertEq(vault.totalBaseAssets(), expectedTotalAssets, "Total base assets should match deposit amount");
        assertEq(vault.totalAssets(), expectedTotalAssets / 1e12, "Total assets should match deposit amount");

        uint256 assetsPerShareBeforeSwap = vault.convertToAssets(1e18);

        // Assert that assets per share remains the same after deposit
        assertEq(
            assetsPerShareBeforeDeposit,
            assetsPerShareBeforeSwap,
            "Asset per share ratio should remain the same after deposit"
        );

        uint256 allocatedUSDC = swapAndAllocateToBuffer(depositAmount);

        // Verify that the allocated WUSDC amount is correct
        // USDE has 18 decimals, USDC has 6 decimals, so we divide by 1e12
        assertEq(
            allocatedUSDC,
            depositAmount / 1e12,
            "Allocated WUSDC should match deposit amount converted to USDC decimals"
        );

        // Ensure withdrawAmount doesn't exceed the allocated WUSDC amount
        withdrawAmount = withdrawAmount <= allocatedUSDC ? withdrawAmount : allocatedUSDC;

        // Calculate expected shares to burn
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);
        // Check convertToAssets before withdrawal
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

        assertEq(assetsPerShareBefore, assetsPerShareBeforeSwap, "Shares to burn should match expected calculation");

        // Withdraw assets from the vault
        vm.startPrank(alice);

        vault.redeem(sharesToBurn, alice, alice);
        vm.stopPrank();

        // Check convertToAssets after withdrawal
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);

        // Assert that the conversion rate is greater than or equal after withdrawal
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );
        // Assert that the conversion rate remains approximately the same
        if (depositAmount >= 1e18) {
            assertApproxEqAbs(
                assetsPerShareBefore, assetsPerShareAfter, 1, "Asset per share ratio should remain constant"
            );
        } else {
            // TODO: fix the error margin here
            // more error at lower amounts
            assertApproxEqAbs(
                assetsPerShareBefore,
                assetsPerShareAfter,
                10 ** IERC20Metadata(MC.USDC).decimals(),
                "Asset per share ratio should remain constant"
            );
        }

        // Verify withdraw was successful
        assertEq(
            vault.balanceOf(alice), sharesReceived - sharesToBurn, "Alice's shares should be reduced by burned amount"
        );
        assertEq(
            vault.totalSupply(),
            initialSupply + sharesReceived - sharesToBurn,
            "Total supply should be reduced by burned amount"
        );
        assertEq(
            vault.totalBaseAssets(),
            expectedTotalAssets - withdrawAmount * 1e12,
            "Total assets should be reduced by withdraw amount"
        );

        assertEq(
            vault.totalAssets(),
            expectedTotalAssets / 1e12 - withdrawAmount,
            "Total assets should match expected value after withdrawal"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn assets");
    }

    function test_Vault_deposit_usde_and_redeem_usdc_success_with_fees(
        uint256 withdrawAmount,
        uint64 withdrawalFee,
        uint256 depositAmount
    ) public {
        withdrawalFee = uint64(bound(withdrawalFee, 1, FeeMath.BASIS_POINT_SCALE / 2));

        depositAmount = bound(depositAmount, 1e12, 100_000 * 1e18);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        withdrawAmount = withdrawAmount / 1e12; // USDC amount
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);

        // Pre-deposit 1 million USDC to the vault
        uint256 preDepositAmount = 1_000_000 * 1e6; // 1 million USDC (6 decimals)
        {
            // Create a depositor account
            address depositor = address(0xDEAD);

            // Give the depositor USDC
            deal(MC.USDC, depositor, preDepositAmount);

            // Deposit USDC to the vault
            vm.startPrank(depositor);
            IERC20(MC.USDC).approve(address(vault), preDepositAmount);
            vault.depositAsset(MC.USDC, preDepositAmount, depositor);
            vm.stopPrank();
        }

        uint256 initialSupply = vault.totalSupply();
        uint256 sharesReceived;
        uint256 expectedTotalAssets;
        uint256 amountToWithdraw = withdrawAmount;

        // Bound withdraw amount to be less than or equal to deposit amount
        {
            vm.prank(alice);
            MockERC20(MC.USDE).mint(depositAmount);

            uint256 assetsPerShareBeforeDeposit = vault.convertToAssets(1e18);

            vm.startPrank(alice);
            IERC20(MC.USDE).approve(address(vault), depositAmount);
            sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
            vm.stopPrank();

            expectedTotalAssets = depositAmount + preDepositAmount * 1e12;
            // total assets are in WUSDC
            assertEq(vault.totalBaseAssets(), expectedTotalAssets, "Total base assets should match deposit amount");
            assertEq(vault.totalAssets(), expectedTotalAssets / 1e12, "Total assets should match deposit amount");

            uint256 assetsPerShareBeforeSwap = vault.convertToAssets(1e18);

            // Assert that assets per share remains the same after deposit
            assertEq(
                assetsPerShareBeforeDeposit,
                assetsPerShareBeforeSwap,
                "Asset per share ratio should remain the same after deposit"
            );

            {
                uint256 allocatedUSDC = swapAndAllocateToBuffer(depositAmount);

                // Verify that the allocated WUSDC amount is correct
                // USDE has 18 decimals, USDC has 6 decimals, so we divide by 1e12
                assertEq(
                    allocatedUSDC,
                    depositAmount / 1e12,
                    "Allocated WUSDC should match deposit amount converted to USDC decimals"
                );

                // Ensure withdrawAmount doesn't exceed the allocated WUSDC amount
                withdrawAmount = withdrawAmount <= allocatedUSDC ? withdrawAmount : allocatedUSDC;
            }

            if (withdrawAmount > vault.maxWithdraw(alice)) {
                amountToWithdraw = vault.maxWithdraw(alice);
            }

            assertEq(
                vault.convertToAssets(1e18),
                assetsPerShareBeforeSwap,
                "Shares to burn should match expected calculation"
            );
        }

        // Check convertToAssets before withdrawal
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

        // Calculate expected shares to burn
        uint256 expectedSharesToBurn = vault.previewWithdraw(amountToWithdraw);
        {
            // Withdraw assets from the vault
            vm.startPrank(alice);
            uint256 totalSharesOfPerformanceFeeRecipientBefore =
                vault.balanceOf(vault.hooks().performanceFeeRecipient());
            uint256 assetsRedeemedToUser = vault.redeem(expectedSharesToBurn, alice, alice);
            uint256 expectedFee = (assetsRedeemedToUser * withdrawalFee) / FeeMath.BASIS_POINT_SCALE;
            uint256 totalSharesOfPerformanceFeeRecipientAfter = vault.balanceOf(vault.hooks().performanceFeeRecipient());
            vm.stopPrank();

            uint256 sharesMintedToPerformanceFeeRecipient =
                totalSharesOfPerformanceFeeRecipientAfter - totalSharesOfPerformanceFeeRecipientBefore;
            assertApproxEqAbs(
                vault.convertToAssets(sharesMintedToPerformanceFeeRecipient),
                expectedFee,
                5,
                "correct fee should be minted"
            );
            assertApproxEqAbs(assetsRedeemedToUser, amountToWithdraw, 5, "correct assets should be redeemed");
            assertEq(
                vault.totalSupply(),
                initialSupply + sharesReceived - expectedSharesToBurn + sharesMintedToPerformanceFeeRecipient,
                "Total supply should be reduced by burned amount"
            );

            {
                // Assert that the conversion rate remains approximately the same
                if (depositAmount >= 1e18) {
                    assertApproxEqAbs(
                        assetsPerShareBefore,
                        vault.convertToAssets(1e18),
                        1,
                        "Asset per share ratio should remain constant"
                    );
                } else {
                    assertApproxEqAbs(
                        assetsPerShareBefore,
                        vault.convertToAssets(1e18),
                        100,
                        "Asset per share ratio should remain constant"
                    );
                }
            }

            // Verify withdraw was successful
            assertEq(
                vault.balanceOf(alice),
                sharesReceived - expectedSharesToBurn,
                "Alice's shares should be reduced by burned amount"
            );
            assertEq(
                vault.totalBaseAssets(),
                expectedTotalAssets - amountToWithdraw * 1e12,
                "Total assets should be reduced by withdraw amount"
            );

            assertEq(
                vault.totalAssets(),
                expectedTotalAssets / 1e12 - amountToWithdraw,
                "Total assets should match expected value after withdrawal"
            );
            assertEq(
                IERC20(MC.USDC).balanceOf(alice), amountToWithdraw, "Alice should have received the withdrawn assets"
            );
        }
    }

    function test_depositAndWithdrawWUSDC_without_fees(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound deposit amount to reasonable values
        vm.assume(depositAmount >= 1); // At least 1 USDC
        vm.assume(depositAmount <= 1_000_000 * 1e6); // Up to 1 million USDC (6 decimals)

        // Ensure withdraw amount is between 0 and deposit amount
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount);

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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        assertApproxEqAbs(sharesBurned, sharesToBurn, 1e12, "correct shares should be burned");
        assertApproxEqAbs(
            vault.convertToAssets(sharesMintedToPerformanceFeeRecipient), expectedFee, 5, "correct fee should be minted"
        );
        assertApproxEqAbs(vault.convertToAssets(1e18), assetsPerShareBefore, 5, "correct asset per share ratio");
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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
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
        vm.assume(depositAmount >= 1); // At least 1 USDC
        vm.assume(depositAmount <= 1_000_000 * 1e6); // Up to 1 million USDC (6 decimals)

        vm.assume(redeemShares > 0);

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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after redemption"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - expectedAssets;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by redeemed amount");
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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        assertApproxEqAbs(vault.convertToAssets(1e18), assetsPerShareBefore, 5, "correct asset per share ratio");
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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
        assertGe(
            assetsPerShareAfter, assetsPerShareBefore, "Asset per share ratio should not decrease after withdrawal"
        );

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore - withdrawAmount;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by withdraw amount");
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
        uint256 assetsPerShareBefore = vault.convertToAssets(1e18);

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
        uint256 assetsPerShareAfter = vault.convertToAssets(1e18);
        assertApproxEqAbs(assetsPerShareAfter, assetsPerShareBefore, 5, "Asset per share ratio should remain same");

        // Check total assets
        uint256 expectedTotalAssetsAfter = totalAssetsBefore;
        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Total assets should be reduced by redeemed amount");
    }
}
