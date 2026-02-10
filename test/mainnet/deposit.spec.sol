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

    function test_Vault_deposit_fixedAmount_success() public {
        address alice = address(0x1);

        // First deposit some assets to have a valid owner with shares
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial conversion rates
        uint256 initialConvertToAssets = vault.convertToAssets(1e18);
        uint256 initialConvertToShares = vault.convertToShares(1e6);

        deal(MC.USDC, alice, 1000e6);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);

        // Assert concrete values for totalAssets and totalSupply increases
        assertEq(vault.totalAssets(), initialTotalAssets + 1000e6, "Total assets should increase by exactly 1000e6");
        assertEq(
            vault.totalSupply(),
            initialTotalSupply + shares,
            "Total supply should increase by the shares returned from deposit"
        );

        // Assert conversion rates stayed the same
        assertEq(vault.convertToAssets(1e18), initialConvertToAssets, "convertToAssets rate should remain unchanged");
        assertEq(vault.convertToShares(1e6), initialConvertToShares, "convertToShares rate should remain unchanged");
    }

    function test_Vault_mint_fixedAmount_success() public {
        address alice = address(0x1);

        // First mint some shares to have a valid owner
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial conversion rates
        uint256 initialConvertToAssets = vault.convertToAssets(1e18);
        uint256 initialConvertToShares = vault.convertToShares(1e6);

        uint256 sharesToMint = 1000e18; // 1000 shares with 18 decimals

        // Calculate required assets for minting these shares
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        deal(MC.USDC, alice, requiredAssets * 10);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), requiredAssets);
        vm.prank(alice);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);

        // Assert concrete values for totalAssets and totalSupply increases
        assertEq(
            vault.totalSupply(),
            initialTotalSupply + sharesToMint,
            "Total supply should increase by exactly the shares minted"
        );
        assertEq(
            vault.totalAssets(),
            initialTotalAssets + assetsUsed,
            "Total assets should increase by the assets used for minting"
        );
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice should have the exact number of shares minted");

        // Assert conversion rates stayed the same
        assertEq(vault.convertToAssets(1e18), initialConvertToAssets, "convertToAssets rate should remain unchanged");

        // assets converted to shares may result in less shares than expected due to rounding
        assertLe(
            vault.convertToShares(1e6),
            initialConvertToShares,
            "convertToShares rate should be less than or equal to the initial convertToShares rate"
        );
        assertApproxEqRel(
            vault.convertToShares(1e6),
            initialConvertToShares,
            1e12,
            "convertToShares rate should remain roughly unchanged"
        );
    }

    function test_Vault_deposit_and_donate_rate_increase() public {
        address alice = address(0x1);
        address donor = address(0x2);

        // Initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Alice deposits USDC
        uint256 depositAmount = 1000e6; // 1000 USDC
        deal(MC.USDC, alice, depositAmount);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Record state after deposit
        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        uint256 totalSupplyAfterDeposit = vault.totalSupply();
        uint256 sharePrice1 = vault.convertToAssets(1e18); // Price per share (18 decimals)

        // Donor donates USDC directly to vault (simulating yield/profit)
        uint256 donationAmount = 500e6; // 500 USDC donation
        deal(MC.USDC, donor, donationAmount);
        vm.prank(donor);
        IERC20(MC.USDC).transfer(address(vault), donationAmount);

        {
            // Check that total assets increased but total supply stayed the same
            uint256 totalAssetsAfterDonation = vault.totalAssets();
            uint256 totalSupplyAfterDonation = vault.totalSupply();
            uint256 sharePrice2 = vault.convertToAssets(1e18); // New price per share

            // Assertions
            assertEq(
                totalAssetsAfterDeposit,
                initialTotalAssets + depositAmount,
                "Total assets should increase by deposit amount"
            );
            assertEq(
                totalSupplyAfterDeposit, initialTotalSupply + shares, "Total supply should increase by shares minted"
            );

            assertEq(
                totalAssetsAfterDonation,
                totalAssetsAfterDeposit + donationAmount,
                "Total assets should increase by donation amount"
            );
            assertEq(
                totalSupplyAfterDonation, totalSupplyAfterDeposit, "Total supply should remain unchanged after donation"
            );

            assertGt(sharePrice2, sharePrice1, "Share price should increase after donation");

            // Verify the rate increase is proportional
            uint256 expectedSharePrice =
                sharePrice1 * (totalAssetsAfterDeposit + donationAmount) / totalAssetsAfterDeposit;
            assertApproxEqAbs(
                sharePrice2, expectedSharePrice, 1, "Share price should increase proportionally to the donation"
            );
        }

        // Verify Alice's shares are worth more now
        uint256 aliceSharesValue = vault.convertToAssets(vault.balanceOf(alice));
        assertGt(aliceSharesValue, depositAmount, "Alice's shares should be worth more than her initial deposit");
    }

    function test_donation_increases_share_price_wusdc() public {
        address alice = address(0x1);
        address donor = address(0x2);

        // Initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Alice deposits USDC
        uint256 depositAmount = 1000e6; // 1000 USDC
        deal(MC.USDC, alice, depositAmount);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Record state after deposit
        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        uint256 totalSupplyAfterDeposit = vault.totalSupply();
        uint256 sharePrice1 = vault.convertToAssets(1e18); // Price per share (18 decimals)

        // Donor obtains WUSDC by depositing USDC into WUSDC contract
        uint256 donationAmount = 500e18; // 500 WUSDC donation (18 decimals)
        uint256 usdcForWusdc = donationAmount / 1e12; // 500 USDC to deposit into WUSDC (6 decimals)
        deal(MC.USDC, donor, usdcForWusdc);
        vm.prank(donor);
        IERC20(MC.USDC).approve(address(wusdc), usdcForWusdc);
        vm.prank(donor);
        wusdc.deposit(usdcForWusdc, donor);
        vm.prank(donor);
        IERC20(address(wusdc)).transfer(address(vault), donationAmount);

        {
            // Check that total assets increased but total supply stayed the same
            uint256 totalAssetsAfterDonation = vault.totalAssets();
            uint256 totalSupplyAfterDonation = vault.totalSupply();
            uint256 sharePrice2 = vault.convertToAssets(1e18); // New price per share

            // Assertions
            assertEq(
                totalAssetsAfterDeposit,
                initialTotalAssets + depositAmount,
                "Total assets should increase by deposit amount"
            );
            assertEq(
                totalSupplyAfterDeposit, initialTotalSupply + shares, "Total supply should increase by shares minted"
            );

            assertEq(
                totalAssetsAfterDonation,
                totalAssetsAfterDeposit + donationAmount / 1e12,
                "Total assets should increase by donation amount"
            );
            assertEq(
                totalSupplyAfterDonation, totalSupplyAfterDeposit, "Total supply should remain unchanged after donation"
            );

            assertGt(sharePrice2, sharePrice1, "Share price should increase after donation");

            // Verify the rate increase is proportional
            uint256 expectedSharePrice =
                sharePrice1 * (totalAssetsAfterDeposit + donationAmount / 1e12) / totalAssetsAfterDeposit;
            assertApproxEqAbs(
                sharePrice2, expectedSharePrice, 1, "Share price should increase proportionally to the donation"
            );
        }

        // Verify Alice's shares are worth more now
        uint256 aliceSharesValue = vault.convertToAssets(vault.balanceOf(alice));
        assertGt(aliceSharesValue, depositAmount, "Alice's shares should be worth more than her initial deposit");
    }
}
