// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, TransparentUpgradeableProxy, IERC4626, Math} from "src/Common.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

interface IAccountingModule {
    function safe() external view returns (address);
}

interface IFlexStrategy {
    function accountingModule() external view returns (address);
}

contract VaultDepositTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    IProvider public provider;

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        // Process accounting to ensure vault is in sync
        vault.processAccounting();

        IAccountingModule accountingModule = IAccountingModule(IFlexStrategy(MC.FLEX_STRATEGY_USDC).accountingModule());

        // Give approval for USDC from SAFE to accounting module
        vm.prank(accountingModule.safe());
        IERC20(MC.USDC).approve(address(accountingModule), type(uint256).max);
    }

    function test_Vault_allocate_withdraw_flex_strategy_usdc() public {
        address alice = address(0x1);
        uint256 depositAmount = 10000e6;

        // Deal USDC to alice
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend USDC
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        // Deposit USDC to vault
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Verify the deposit was successful
        assertGt(shares, 0, "Should receive shares from deposit");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice should have no USDC left");
        assertEq(vault.balanceOf(alice), shares, "Alice should have received shares");

        uint256 allocationAmount = 1000e6;
        // Get initial balances
        uint256 initialVaultUSDC = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 initialStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();

        ProcessorUtils.allocateToERC4626(address(vault), MC.USDC, MC.FLEX_STRATEGY_USDC, allocationAmount, PROCESSOR);

        // Verify vault USDC balance decreased by allocation amount
        uint256 finalVaultUSDC = IERC20(MC.USDC).balanceOf(address(vault));
        assertEq(
            finalVaultUSDC,
            initialVaultUSDC - allocationAmount,
            "Vault USDC balance should decrease by allocation amount"
        );

        // Verify strategy total assets increased by allocation amount
        uint256 finalStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();
        assertEq(
            finalStrategyTotalAssets,
            initialStrategyTotalAssets + allocationAmount,
            "Strategy total assets should increase by allocation amount"
        );

        // Now withdraw the allocated assets from the strategy
        uint256 withdrawAmount = allocationAmount / 2;

        // Get balances before withdrawal
        uint256 preWithdrawVaultUSDC = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 preWithdrawStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();
        // Withdraw directly using processor
        // Get vault total assets before withdrawal
        uint256 preWithdrawVaultTotalAssets = vault.totalAssets();

        {
            address[] memory targets = new address[](1);
            targets[0] = MC.FLEX_STRATEGY_USDC;

            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            bytes[] memory data = new bytes[](1);
            data[0] = abi.encodeWithSignature(
                "withdraw(uint256,address,address)", withdrawAmount, address(vault), address(vault)
            );

            vm.prank(PROCESSOR);
            vault.processor(targets, values, data);
        }

        // Verify vault USDC balance increased by withdrawal amount
        uint256 postWithdrawVaultUSDC = IERC20(MC.USDC).balanceOf(address(vault));
        assertEq(
            postWithdrawVaultUSDC,
            preWithdrawVaultUSDC + withdrawAmount,
            "Vault USDC balance should increase by withdrawal amount"
        );

        // Verify strategy total assets decreased by withdrawal amount
        uint256 postWithdrawStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();
        assertEq(
            postWithdrawStrategyTotalAssets,
            preWithdrawStrategyTotalAssets - withdrawAmount,
            "Strategy total assets should decrease by withdrawal amount"
        );

        vault.processAccounting();

        // Verify vault total assets stayed the same
        uint256 postWithdrawVaultTotalAssets = vault.totalAssets();
        assertEq(
            postWithdrawVaultTotalAssets,
            preWithdrawVaultTotalAssets,
            "Vault total assets should remain unchanged after withdrawal"
        );
    }

    function test_Vault_allocate_withdraw_flex_strategy_and_deploy_to_spv() public {
        address alice = address(0x1);
        uint256 depositAmount = 10000e6;

        // Deal USDC to alice
        deal(MC.USDC, alice, depositAmount);

        // Approve vault to spend USDC
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);

        address safe = IAccountingModule(IFlexStrategy(MC.FLEX_STRATEGY_USDC).accountingModule()).safe();

        // Deposit USDC to vault
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 safeBalanceBefore = IERC20(MC.USDC).balanceOf(safe);

        uint256 allocationAmount = 1000e6;
        // Get initial balances
        uint256 initialVaultUSDC = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 initialStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();

        ProcessorUtils.allocateToERC4626(address(vault), MC.USDC, MC.FLEX_STRATEGY_USDC, allocationAmount, PROCESSOR);

        IVault(MC.FLEX_STRATEGY_USDC).processAccounting();
        vault.processAccounting();

        address spv = address(0x2345226326);

        // Get balances before transfer to SPV
        uint256 preTransferStrategyTotalAssets = IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets();
        uint256 preTransferVaultTotalAssets = vault.totalAssets();

        assertEq(
            IERC20(MC.USDC).balanceOf(safe),
            allocationAmount + safeBalanceBefore,
            "SAFE should have the allocation amount + safeBalanceBefore"
        );

        vm.startPrank(safe);
        IERC20(MC.USDC).transfer(spv, allocationAmount);
        vm.stopPrank();

        IVault(MC.FLEX_STRATEGY_USDC).processAccounting();
        vault.processAccounting();

        assertEq(IERC20(MC.USDC).balanceOf(spv), allocationAmount, "SPV should have received the allocation amount");
        assertEq(IERC20(MC.USDC).balanceOf(safe), safeBalanceBefore, "SAFE should have safeBalanceBefore USDC left");

        assertEq(
            IERC4626(MC.FLEX_STRATEGY_USDC).totalAssets(),
            preTransferStrategyTotalAssets,
            "Strategy total assets should remain unchanged after transfer to SPV"
        );

        assertEq(
            vault.totalAssets(),
            preTransferVaultTotalAssets,
            "Vault total assets should remain unchanged after transfer to SPV"
        );
    }
}
