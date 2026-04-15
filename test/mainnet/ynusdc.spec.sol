// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {IVault} from "src/interface/IVault.sol";

contract YnUSDCTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();
    }


    function test_deposit_fully_to_ynusdc(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1000, 1_000_000 * 1e6);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        uint256 totalAssetsOfVaultBefore = vault.totalAssets();
        uint256 totalBaseAssetsOfVaultBefore = vault.totalBaseAssets();
        uint256 totalSupplyOfVaultBefore = vault.totalSupply();
        uint256 initialUSDCBalanceOfVault = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 expectedSharesToReceive = IERC4626(vault).previewDeposit(depositAmount);

        _depositAssetToVault(MC.USDC, depositAmount, alice);

        vault.processAccounting();

        assertEq(
            vault.totalAssets(),
            depositAmount + totalAssetsOfVaultBefore,
            "Vault should have the same total assets as the deposit amount"
        );
        assertEq(
            vault.totalBaseAssets(),
            depositAmount * 1e12 + totalBaseAssetsOfVaultBefore,
            "Vault should have the same total base assets as the deposit amount scaled by 1e12"
        );
        assertEq(
            vault.totalSupply(),
            expectedSharesToReceive + totalSupplyOfVaultBefore,
            "Vault should have the same total supply as the expected shares to receive"
        );
        assertGt(vault.balanceOf(alice), 0, "Alice should have received shares of vault");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            depositAmount + initialUSDCBalanceOfVault,
            "USDC balance of vault should increase by deposit amount"
        );

        // vault state before deposit to ynUSDC
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 ynusdcBalanceOfVaultBefore = IERC20(MC.YNUSDC).balanceOf(address(vault));

        depositToYnUSDC(depositAmount);

        uint256 usdcBalanceOfVaultAfter = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 ynusdcBalanceOfVaultAfter = IERC20(MC.YNUSDC).balanceOf(address(vault));

        // ynUSDC is a yield-bearing ERC4626 vault, so small rounding differences are expected
        assertApproxEqAbs(
            vault.totalSupply(),
            vaultTotalSupplyBefore,
            1e7,
            "Vault total supply should be similar after ynUSDC allocation"
        );
        assertApproxEqAbs(
            vault.totalAssets(), vaultAssetsBefore, 1e7, "Vault total assets should be similar after ynUSDC allocation"
        );

        assertTrue(
            ynusdcBalanceOfVaultAfter > ynusdcBalanceOfVaultBefore, "Vault should have ynUSDC balance after deposit"
        );
        assertEq(
            usdcBalanceOfVaultBefore - usdcBalanceOfVaultAfter,
            depositAmount,
            "USDC balance of vault should decrease by deposit amount"
        );
    }

    function test_deposit_and_withdraw_from_ynusdc(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 2e6, 1_000_000 * 1e6);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount - 1000);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        uint256 usdcBalanceOfVaultBefore;
        {
            uint256 totalAssetsOfVaultBefore = vault.totalAssets();
            uint256 totalBaseAssetsOfVaultBefore = vault.totalBaseAssets();
            uint256 totalSupplyOfVaultBefore = vault.totalSupply();
            usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 expectedSharesToReceive = IERC4626(vault).previewDeposit(depositAmount);

            _depositAssetToVault(MC.USDC, depositAmount, alice);

            vault.processAccounting();

            assertEq(
                vault.totalAssets(),
                depositAmount + totalAssetsOfVaultBefore,
                "Vault should have the same total assets as the deposit amount"
            );
            assertEq(
                vault.totalBaseAssets(),
                depositAmount * 1e12 + totalBaseAssetsOfVaultBefore,
                "Vault should have the same total base assets as the deposit amount scaled by 1e12"
            );
            assertEq(
                vault.totalSupply(),
                expectedSharesToReceive + totalSupplyOfVaultBefore,
                "Vault should have the same total supply as the expected shares to receive"
            );
        }

        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        depositToYnUSDC(depositAmount);

        uint256 ynusdcBalanceOfVaultBefore = IERC20(MC.YNUSDC).balanceOf(address(vault));
        usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        assertTrue(ynusdcBalanceOfVaultBefore > 0, "Vault should have ynUSDC shares after deposit");

        uint256 sharesToWithdraw = IERC4626(MC.YNUSDC).previewWithdraw(withdrawAmount);

        // Withdraw from ynUSDC vault via redeem
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = MC.YNUSDC;
        values[0] = 0;
        data[0] =
            abi.encodeWithSignature("redeem(uint256,address,address)", sharesToWithdraw, address(vault), address(vault));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();

        vault.processAccounting();

        uint256 ynusdcBalanceOfVaultAfter = IERC20(MC.YNUSDC).balanceOf(address(vault));
        assertEq(
            ynusdcBalanceOfVaultBefore - ynusdcBalanceOfVaultAfter,
            sharesToWithdraw,
            "ynUSDC balance of vault should decrease by shares withdrawn"
        );
        assertApproxEqAbs(
            IERC20(MC.USDC).balanceOf(address(vault)) - usdcBalanceOfVaultBefore,
            withdrawAmount,
            100,
            "USDC balance of vault should increase by withdraw amount"
        );
        // ynUSDC is a yield-bearing ERC4626 vault; processAccounting may mint
        // small performance fee shares from rounding differences in rates
        vm.assertApproxEqRel(
            vault.totalSupply(),
            vaultTotalSupplyBefore,
            2e14,
            "Vault total supply should be similar after ynUSDC allocation and withdrawal"
        );
        vm.assertApproxEqRel(
            vault.totalAssets(),
            vaultAssetsBefore,
            2e14,
            "Vault total assets should be similar after ynUSDC allocation and withdrawal"
        );
    }

    function depositToYnUSDC(uint256 depositAmount) internal {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = MC.USDC;
        values[0] = 0;
        data[0] = abi.encodeCall(IERC20.approve, (MC.YNUSDC, depositAmount));

        targets[1] = MC.YNUSDC;
        values[1] = 0;
        data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();

        vault.processAccounting();
    }

    function _depositAssetToVault(address asset, uint256 amount, address user) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(vault), amount);
        vault.depositAsset(asset, amount, user);
        vm.stopPrank();
    }
}
