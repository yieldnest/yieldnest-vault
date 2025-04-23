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
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";

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

    function swapAndAllocateToBuffer(uint256 depositAmount) internal returns (uint256) {
        // Calculate how much USDC we expect to receive for our USDE
        uint256 expectedUsdcAmount = swapper.previewSwap(MC.USDE, MC.USDC, depositAmount);
        // Verify the expected USDC amount is depositAmount / 12
        assertEq(expectedUsdcAmount, depositAmount / 1e12, "Expected USDC amount should be depositAmount / 1e12");

        // Prepare the calldata for the swap function
        bytes memory swapCalldata = abi.encodeWithSelector(MockSwapper.swap.selector, MC.USDE, MC.USDC, depositAmount);

        // First approve USDE to the swapper, then execute the swap
        address[] memory targets = new address[](2);
        targets[0] = address(MC.USDE);
        targets[1] = address(swapper);

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, address(swapper), depositAmount);
        calldatas[1] = swapCalldata;

        vm.prank(PROCESSOR);
        bytes[] memory returnData = vault.processor(targets, new uint256[](2), calldatas);
        uint256 receivedUsdc = abi.decode(returnData[1], (uint256));

        // Verify the swap was successful
        assertEq(receivedUsdc, expectedUsdcAmount, "Received USDC should match expected amount");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), receivedUsdc, "Vault should have received the USDC");

        uint256 wusdcBalance;
        {
            // Wrap USDC to WUSDC
            targets = new address[](2);
            targets[0] = MC.USDC;
            targets[1] = address(wusdc);

            calldatas = new bytes[](2);
            calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, address(wusdc), receivedUsdc);
            calldatas[1] = abi.encodeWithSelector(WrappedToken.deposit.selector, receivedUsdc, address(vault));

            vm.prank(PROCESSOR);
            vault.processor(targets, new uint256[](2), calldatas);

            wusdcBalance = IERC20(address(wusdc)).balanceOf(address(vault));

            // Verify the wrapping was successful
            assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault should have wrapped all USDC");
            assertEq(
                IERC20(address(wusdc)).balanceOf(address(vault)),
                receivedUsdc * 1e12,
                "Vault should have received WUSDC"
            );
        }

        // Allocate the received USDC to the buffer
        // First approve USDC to the buffer
        targets = new address[](2);
        targets[0] = address(wusdc);
        targets[1] = MC.BUFFER;

        calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(IERC20.approve.selector, MC.BUFFER, wusdcBalance);
        calldatas[1] = abi.encodeWithSelector(IERC4626.deposit.selector, wusdcBalance, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, new uint256[](2), calldatas);

        // Verify the buffer deposit was successful
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault should have deposited all USDC to buffer");
        assertEq(IERC20(MC.BUFFER).balanceOf(address(vault)), wusdcBalance, "Vault should have received buffer shares");
        return wusdcBalance;
    }

    function test_Vault_deposit_and_withdraw_success(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount >= 1e12); // enough decimal points to be non-zero in USDC
        vm.assume(depositAmount <= 100_000 * 1e18);

        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount);

        // Bound withdraw amount to be less than or equal to deposit amount

        withdrawAmount = withdrawAmount / 1e12; // USDC amount

        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        uint256 expectedTotalAssets = depositAmount;
        // total assets are in USDC
        assertEq(vault.totalAssets(), expectedTotalAssets, "Total assets should match deposit amount");

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
        assertEq(
            vault.totalAssets(),
            expectedTotalAssets - withdrawAmount,
            "Total assets should be reduced by withdraw amount"
        );
        assertEq(IERC20(wusdc).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn assets");
    }

    function test_Vault_deposit_and_redeem_success(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount >= 1e12); // enough decimal points to be non-zero in USDC
        vm.assume(depositAmount <= 100_000 * 1e18);

        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= depositAmount);

        // Bound withdraw amount to be less than or equal to deposit amount

        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        uint256 assetsPerShareBeforeDeposit = vault.convertToAssets(1e18);

        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        uint256 expectedTotalAssets = depositAmount;
        // total assets are in WUSDC
        assertEq(vault.totalAssets(), expectedTotalAssets, "Total assets should match deposit amount");

        uint256 assetsPerShareBeforeSwap = vault.convertToAssets(1e18);

        // Assert that assets per share remains the same after deposit
        assertEq(
            assetsPerShareBeforeDeposit,
            assetsPerShareBeforeSwap,
            "Asset per share ratio should remain the same after deposit"
        );

        uint256 allocatedWusdc = swapAndAllocateToBuffer(depositAmount);

        // Verify that the allocated WUSDC amount is correct
        // USDE has 18 decimals, USDC has 6 decimals, so we divide by 1e12
        assertEq(
            allocatedWusdc,
            depositAmount / 1e12 * 1e12,
            "Allocated WUSDC should match deposit amount converted to USDC decimals"
        );

        // Ensure withdrawAmount doesn't exceed the allocated WUSDC amount
        withdrawAmount = withdrawAmount <= allocatedWusdc ? withdrawAmount : allocatedWusdc;

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
        assertEq(vault.totalSupply(), sharesReceived - sharesToBurn, "Total supply should be reduced by burned amount");
        assertEq(
            vault.totalAssets(),
            expectedTotalAssets - withdrawAmount,
            "Total assets should be reduced by withdraw amount"
        );
        assertEq(IERC20(wusdc).balanceOf(alice), withdrawAmount, "Alice should have received the withdrawn assets");
    }
}
