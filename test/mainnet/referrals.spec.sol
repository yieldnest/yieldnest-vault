// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract VaultReferralsTest is BaseIntegrationTest {
    XReferralAdapter xReferralAdapter;

    function setUp() public override {
        super.setUp();

        xReferralAdapter = XReferralAdapter(MC.X_REFERRAL_ADAPTER);
    }

    function test_depositWithReferral(uint256 depositAmount, uint256 donationAmount) public {
        // Assuming the Vault contract has a deposit function that accepts a referral code
        address usdcTokenAddress = MC.USDC; // Assuming MC.USDC is the address of the USDC token
        address referralCode = address(0xA000A); // Using the xReferralAdapter as the referral code

        // Ensure depositAmount and donationAmount are within reasonable bounds
        depositAmount = bound(depositAmount, 1 * 10 ** 6, 1_000_000 * 10 ** 6); // Bound depositAmount between 1 USDC and 10,000 USDC
        donationAmount = bound(donationAmount, 1 * 10 ** 6, 5_000_000 * 10 ** 6); // Bound donationAmount between 1 USDC and 5,000 USDC

        {
            // Define Charlie's address
            address charlie = address(0xC0C); // Example address for Charlie

            // Ensure Charlie has enough USDC balance
            deal(usdcTokenAddress, charlie, donationAmount);
            vm.startPrank(charlie);
            IERC20(usdcTokenAddress).transfer(address(xReferralAdapter), donationAmount);
            vm.stopPrank();
        }

        // Ensure Bob has enough USDC balance
        address bob = address(0xB0B); // Example address for Bob

        // Use the `deal` function to set Bob's USDC balance to ensure he has enough for the deposit
        deal(usdcTokenAddress, bob, depositAmount);
        uint256 bobInitialBalance = IERC20(usdcTokenAddress).balanceOf(bob);
        require(bobInitialBalance >= depositAmount, "Bob does not have enough USDC");

        // Assert initial totalSupply and totalAssets
        uint256 initialTotalSupply = IERC20(address(vault)).totalSupply();
        uint256 initialTotalAssets = vault.totalAssets();

        // Assert that Bob has shares equal to convertToShares
        uint256 expectedShares = vault.convertToShares(depositAmount);

        // Call the depositAssetWithReferral function on the xReferralAdapter as Bob
        vm.startPrank(bob); // Use vm.prank to simulate the call from Bob's address
        IERC20(usdcTokenAddress).approve(address(xReferralAdapter), depositAmount);
        uint256 sharesReceived = xReferralAdapter.depositAssetWithReferral(
            address(vault), // _vault
            usdcTokenAddress, // asset
            depositAmount, // assets
            referralCode, // referrer
            bob // receiver
        );
        vm.stopPrank();

        uint256 bobShares = IERC20(address(vault)).balanceOf(bob);
        assertEq(sharesReceived, expectedShares, "Shares received do not match the expected shares after deposit");
        assertEq(bobShares, expectedShares, "Bob's shares do not match the expected shares after deposit");

        // Assert that Bob has less assets
        uint256 bobFinalBalance = IERC20(usdcTokenAddress).balanceOf(bob);
        assertEq(
            bobFinalBalance,
            bobInitialBalance - depositAmount,
            "Bob's final balance does not match the expected balance after deposit"
        );

        // Assert that totalSupply increased
        uint256 totalSupply = IERC20(address(vault)).totalSupply();
        assertEq(
            totalSupply,
            initialTotalSupply + expectedShares,
            "Total supply does not match the expected shares after deposit"
        );

        // Assert that totalAssets increased
        uint256 totalAssets = vault.totalAssets();
        assertEq(
            totalAssets,
            initialTotalAssets + depositAmount,
            "Total assets do not match the deposit amount after deposit"
        );
    }
}
