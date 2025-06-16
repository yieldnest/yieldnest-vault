// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";

contract SuperUSDCTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();
        bufferStrategy = MC.MORPHO_GAUNTLET_USDC_VAULT;
    }

    function test_deposit_fully_to_superusdc_vault(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1000, 5_000_000 * 1e6);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        uint256 totalAssetsOfVaultBefore = vault.totalAssets();
        uint256 totalBaseAssetsOfVaultBefore = vault.totalBaseAssets();
        uint256 totalSupplyOfVaultBefore = vault.totalSupply();
        uint256 initialUSDCBalanceOfVault = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 expectedSharesToReceive = IERC4626(vault).previewDeposit(depositAmount);

        _depositAssetToVault(MC.USDC, depositAmount, alice);

        // Process accounting
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
            "USDC balance of vault should decrease by deposit amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "USDC balance of alice should be 0");

        // vault state before deposit to superusdc vault
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceOfVaultBefore = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));

        depositToSuperUSDCVault(depositAmount);

        uint256 usdcBalanceOfVaultAfter = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceOfVaultAfter = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));

        totalSupplyInvariant(vaultTotalSupplyBefore);
        totalAssetsInvariant(vaultAssetsBefore);

        assertTrue(
            superUSDCBalanceOfVaultAfter > superUSDCBalanceOfVaultBefore,
            "Vault should have SuperUSDC balance after deposit"
        );
        assertEq(
            usdcBalanceOfVaultBefore - usdcBalanceOfVaultAfter,
            depositAmount,
            "USDC balance of vault should decrease by deposit amount"
        );
    }

    function test_deposit_partially_to_superusdc_vault(uint256 userDepositAmount, uint256 superUSDCVaultDepositAmount)
        public
    {
        userDepositAmount = bound(userDepositAmount, 1000, 5_000_000 * 1e6);
        superUSDCVaultDepositAmount = bound(superUSDCVaultDepositAmount, 1000, userDepositAmount);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, userDepositAmount);

        uint256 totalAssetsOfVaultBefore = vault.totalAssets();
        uint256 totalBaseAssetsOfVaultBefore = vault.totalBaseAssets();
        uint256 totalSupplyOfVaultBefore = vault.totalSupply();
        uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 expectedSharesToReceive = IERC4626(vault).previewDeposit(userDepositAmount);

        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        // Process accounting
        vault.processAccounting();

        assertEq(
            vault.totalAssets(),
            userDepositAmount + totalAssetsOfVaultBefore,
            "Vault should have the same total assets as the user deposit amount"
        );
        assertEq(
            vault.totalBaseAssets(),
            userDepositAmount * 1e12 + totalBaseAssetsOfVaultBefore,
            "Vault should have the same total base assets as the user deposit amount scaled by 1e12"
        );
        assertEq(
            vault.totalSupply(),
            expectedSharesToReceive + totalSupplyOfVaultBefore,
            "Vault should have the same total supply as the expected shares to receive"
        );
        assertGt(vault.balanceOf(alice), 0, "Alice should have received shares of vault");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            userDepositAmount + usdcBalanceOfVaultBefore,
            "USDC balance of vault should decrease by user deposit amount"
        );
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "USDC balance of alice should be 0");

        // vault state before deposit to superusdc vault
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceOfVaultBefore = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));

        depositToSuperUSDCVault(superUSDCVaultDepositAmount);

        uint256 usdcBalanceOfVaultAfter = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceOfVaultAfter = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));

        totalSupplyInvariant(vaultTotalSupplyBefore);
        totalAssetsInvariant(vaultAssetsBefore);

        assertTrue(
            superUSDCBalanceOfVaultAfter > superUSDCBalanceOfVaultBefore,
            "Vault should have SuperUSDC balance after deposit"
        );
        assertEq(
            usdcBalanceOfVaultBefore - usdcBalanceOfVaultAfter,
            superUSDCVaultDepositAmount,
            "USDC balance of vault should decrease by superUSDC vault deposit amount"
        );
    }

    function test_deposit_and_withdraw_from_superusdc_vault(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 2e6, 25_00_000 * 1e6);
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

            // Process accounting
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
                depositAmount + usdcBalanceOfVaultBefore,
                "USDC balance of vault should decrease by deposit amount"
            );
            assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "USDC balance of alice should be 0");
        }

        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        depositToSuperUSDCVault(depositAmount);

        uint256 superUSDCBalanceOfVaultBefore = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        assertTrue(superUSDCBalanceOfVaultBefore > 0, "Vault should have SuperUSDC shares after deposit");

        uint256 sharesToWithdraw = IERC4626(MC.SUPER_USDC_VAULT).previewWithdraw(withdrawAmount);

        // Withdraw from SuperUSDC vault
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = MC.SUPER_USDC_VAULT;
        values[0] = 0;
        data[0] =
            abi.encodeWithSignature("redeem(uint256,address,address)", sharesToWithdraw, address(vault), address(vault));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();

        // Process accounting
        vault.processAccounting();

        uint256 superUSDCBalanceOfVaultAfter = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        assertEq(
            superUSDCBalanceOfVaultBefore - superUSDCBalanceOfVaultAfter,
            sharesToWithdraw,
            "SuperUSDC balance of vault should decrease by shares withdrawn"
        );
        assertApproxEqAbs(
            IERC20(MC.USDC).balanceOf(address(vault)) - usdcBalanceOfVaultBefore,
            withdrawAmount,
            100,
            "USDC balance of vault should increase by withdraw amount"
        );
        totalSupplyInvariant(vaultTotalSupplyBefore);
        totalAssetsInvariant(vaultAssetsBefore);
    }

    function depositToSuperUSDCVault(uint256 depositAmount) internal {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = MC.USDC;
        values[0] = 0;
        data[0] = abi.encodeCall(IERC20.approve, (MC.SUPER_USDC_VAULT, depositAmount));

        targets[1] = MC.SUPER_USDC_VAULT;
        values[1] = 0;
        data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();

        // Process accounting
        vault.processAccounting();
    }

    function _depositAssetToVault(address asset, uint256 amount, address user) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(vault), amount);
        vault.depositAsset(asset, amount, user);
        vm.stopPrank();
    }
}
