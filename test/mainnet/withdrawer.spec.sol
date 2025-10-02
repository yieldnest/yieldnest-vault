// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "src/interface/IVault.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IAccessControl} from "src/Common.sol";

contract WithdrawerTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;

    function setUp() public {
        (vault,) = BaseTest.deploy();
    }

    function test_Withdrawer_views() public view {
        assertTrue(withdrawer.getHasAllocator(), "Withdrawer should have allocators");
        assertTrue(withdrawer.getAssetWithdrawable(MC.USDC), "Withdrawer should have WETH withdrawable");
        assertEq(withdrawer.asset(), MC.USDC, "Withdrawer should have WETH as the main asset");
        assertFalse(withdrawer.alwaysComputeTotalAssets(), "Withdrawer should not always compute total assets");
        assertFalse(withdrawer.countNativeAsset(), "Withdrawer should not count native asset");
        assertEq(withdrawer.defaultAssetIndex(), 1, "Withdrawer should have WETH as the default asset");
        assertEq(withdrawer.decimals(), 18, "Withdrawer should have 18 decimals");
    }

    function test_Withdrawer_deposit_and_withdraw_usdc(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount);

        uint256 totalAssetsBefore = vault.totalAssets();

        {
            // Give USDC to alice and have her deposit into the vault
            address alice = makeAddr("alice");
            deal(MC.USDC, alice, depositAmount);

            vm.startPrank(alice);
            IERC20(MC.USDC).approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        ProcessorUtils.allocateToERC4626(address(vault), MC.USDC, address(withdrawer), depositAmount, PROCESSOR);

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 totalAssetsAfter = vault.totalAssets();
        // Assert that totalAssetsAfter is approximately equal to totalAssetsBefore + depositAmount
        // Allow a small absolute difference due to rounding, e.g., 1 wei
        vm.assertApproxEqAbs(
            totalAssetsAfter,
            totalAssetsBefore + depositAmount,
            1,
            "totalAssetsAfter should be approx totalAssetsBefore + depositAmount"
        );

        // Withdraw USDC from the withdrawer using ProcessorUtils
        ProcessorUtils.withdrawFromERC4626(address(vault), address(withdrawer), withdrawAmount, PROCESSOR);

        vm.assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore + depositAmount,
            1,
            "totalAssetsAfter should be approx totalAssetsAfter - withdrawAmount"
        );
    }

    function test_Withdrawer_deposit_and_withdraw_fxbase(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6);

        {
            // Give USDC to alice and have her deposit into the vault
            address alice = makeAddr("alice");
            deal(MC.USDC, alice, depositAmount);

            vm.startPrank(alice);
            IERC20(MC.USDC).approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        // Allocate USDC from the vault to fxBASE using the processor
        ProcessorUtils.depositToFxBase(address(vault), depositAmount, PROCESSOR);

        // Optionally, assert that the vault's fxBASE balance increased as expected
        uint256 fxBaseBalance = IERC20(MC.FXBASE).balanceOf(address(vault));

        // Record totalBaseAssets before allocation
        uint256 totalBaseAssetsBeforeAllocation = vault.totalBaseAssets();

        // Allocate fxBASE from the vault to the withdrawer using depositAsset (allocateToERC4626MAX)
        ProcessorUtils.allocateToERC4626MAX(address(vault), MC.FXBASE, address(withdrawer), fxBaseBalance, PROCESSOR);

        vault.processAccounting();

        withdrawer.processAccounting();
        vault.processAccounting();

        // Assert that the withdrawer received the fxBASE
        assertEq(
            IERC20(MC.FXBASE).balanceOf(address(withdrawer)), fxBaseBalance, "Withdrawer should have received fxBASE"
        );

        // Assert that totalBaseAssets remains approximately constant (allowing for rounding error)
        vm.assertApproxEqAbs(
            vault.totalBaseAssets(),
            totalBaseAssetsBeforeAllocation,
            1,
            "Vault totalBaseAssets should remain approx constant after allocating fxBASE to withdrawer"
        );
    }

    function test_withdrawer_arbitrary_address_deposit_reverts() public {
        address arbitraryUser = makeAddr("arbitraryUser");
        deal(MC.USDC, arbitraryUser, 1e18);
        vm.startPrank(arbitraryUser);
        IERC20(MC.USDC).approve(address(withdrawer), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(arbitraryUser),
                withdrawer.ALLOCATOR_ROLE()
            )
        );
        withdrawer.depositAsset(MC.USDC, 1e18, arbitraryUser);
        vm.stopPrank();
    }
}
