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

contract VaultDepositTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    IProvider public provider;

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_Vault_allocate_to_flex_strategy_usdc() public {
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
    }
}
