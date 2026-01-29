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
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";

contract Vault6DecimalsBaseDepositUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;

    WrappedToken public wusdc;

    function setUp() public {
        SetupBase6DecimalsVault setupVault = new SetupBase6DecimalsVault();
        (vault,) = setupVault.setup();
        wusdc = setupVault.wusdc();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function test_Vault_previewDeposit_0_wei() public {
        uint256 assets = 0;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, 0, "Preview deposit does not match expected shares");
    }

    function test_Vault_previewDeposit_1_wei() public {
        uint256 assets = 1 wei;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, 1e12, "Preview deposit does not match expected shares");
    }

    function test_Vault_initial_deposit_success(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        // Bound deposit amount between 10 and 100k USDC (6 decimals)
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 * 1e6) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Approve vault to spend Alice's wUSDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.assume(sharesMinted > 0);

        // Check rate after deposit is the same
        uint256 afterRate = vault.convertToAssets(1e18);
        assertEq(initialRate, afterRate, "Conversion rate changed after deposit");

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");
        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault did not receive USDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - depositAmount,
            "Alice's USDC balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that shares minted is depositAmount * 1e12 (converting from 6 to 18 decimals)
        assertEq(sharesMinted, depositAmount * 1e12, "Incorrect number of shares minted");
        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), depositAmount * 1e12, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_depositAsset_USDE_success(uint256 depositAmount) public {
        // Assume reasonable deposit amount to avoid overflow and unrealistic values
        vm.assume(depositAmount > 1e12 && depositAmount <= 1_000_000_000e18);

        // Give Alice USDE
        deal(MC.USDE, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Record assets value before deposit
        uint256 assetsBeforeDeposit = vault.convertToAssets(1e18);

        // Deposit USDE using depositAsset
        uint256 sharesMinted = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        // Verify convertToAssets stayed the same for existing shares
        uint256 assetsAfterDeposit = vault.convertToAssets(1e18);
        assertEq(assetsBeforeDeposit, assetsAfterDeposit, "convertToAssets should remain the same for existing shares");

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), depositAmount, "Vault did not receive USDE");

        // Check that Alice's USDE balance decreased
        assertEq(
            IERC20(MC.USDE).balanceOf(alice),
            INITIAL_BALANCE - depositAmount,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Since USDE has 18 decimals but is valued at 1 USD, the shares should be depositAmount / 1e12
        // (converting from 18 to 6 decimals for USD value)
        assertApproxEqAbs(sharesMinted, depositAmount, 1, "Incorrect number of shares minted");

        // Check that total assets increased by the USD value of USDE (depositAmount / 1e12)
        assertEq(vault.totalBaseAssets(), depositAmount, "Total assets did not increase correctly");
        assertEq(vault.totalAssets(), depositAmount / 1e12, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_USDC_deposit_then_depositAsset_USDE_success(
        uint256 usdeDepositAmount,
        uint256 usdcDepositAmount
    ) public {
        // Assume reasonable deposit amounts to avoid overflow and unrealistic values
        vm.assume(usdeDepositAmount > 1e18 && usdeDepositAmount <= 1_000_000_000e18);
        vm.assume(usdcDepositAmount > 1e6 && usdcDepositAmount <= 1_000_000_000e6);

        // Give Alice an initial USDC balance
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Give Alice USDE
        deal(MC.USDE, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");

        // Check that Alice's USDE balance decreased
        assertEq(
            IERC20(MC.USDE).balanceOf(alice),
            INITIAL_BALANCE - usdeDepositAmount,
            "Alice's USDE balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares for USDE deposit
        assertEq(
            vault.balanceOf(alice),
            sharesMintedFromUSDC + sharesMintedFromUSDE,
            "Alice did not receive the correct amount of shares from USDE deposit"
        );

        // Since USDE has 18 decimals but is valued at 1 USD, the shares should be usdeDepositAmount / 1e12
        // (converting from 18 to 6 decimals for USD value)
        assertApproxEqAbs(sharesMintedFromUSDE, usdeDepositAmount, 1, "Incorrect number of shares minted from USDE");
        // Assert that the shares minted from USDE deposit is less than or equal to the usdeDepositAmount
        assertLe(sharesMintedFromUSDE, usdeDepositAmount, "Shares minted from USDE deposit exceed the deposit amount");

        // Check that total assets increased by the USD value of USDE (usdeDepositAmount / 1e12) and USDC (usdcDepositAmount)
        assertEq(
            vault.totalBaseAssets(),
            usdeDepositAmount + usdcDepositAmount * 1e12,
            "Total assets did not increase correctly"
        );
        assertEq(
            vault.totalAssets(), usdeDepositAmount / 1e12 + usdcDepositAmount, "Total assets did not increase correctly"
        );
    }

    function test_Vault_convertToAssetsForAsset_USDE_beforeDeposit() public view {
        uint256 sharesAmount = 1000e18;

        // Cast vault to PublicViewsVault to access the public conversion functions
        PublicViewsVault publicVault = PublicViewsVault(payable(address(vault)));

        // Test conversion before any deposits are made
        (uint256 assets, uint256 baseAssets) =
            publicVault.convertToAssetsForAsset(MC.USDE, sharesAmount, Math.Rounding.Floor);

        // Since USDE has 18 decimals but is valued at 1 USD, the assets should be equal to shares
        // and baseAssets should be shares / 1e12 (converting from 18 to 6 decimals for USD value)
        assertEq(assets, sharesAmount, "Incorrect assets conversion");
        assertEq(baseAssets, sharesAmount, "Incorrect baseAssets conversion");

        // Verify the reverse conversion as well
        (uint256 sharesBack, uint256 baseAssetsBack) =
            publicVault.convertToSharesForAsset(MC.USDE, assets, Math.Rounding.Floor);

        assertEq(sharesBack, sharesAmount, "Reverse conversion to shares failed");
        assertEq(baseAssetsBack, baseAssets, "Reverse conversion to baseAssets failed");

        // Test direct conversion functions
        uint256 convertedBaseAssets = publicVault.convertAssetToBase(MC.USDE, sharesAmount);
        assertEq(convertedBaseAssets, sharesAmount, "Direct asset to base conversion failed");

        uint256 convertedAssets = publicVault.convertBaseToAsset(MC.USDE, convertedBaseAssets);
        assertEq(convertedAssets, sharesAmount, "Direct base to asset conversion failed");
    }

    function test_Vault_convertToSharesForAsset_USDC_vs_USDE() public view {
        uint256 assetsAmount = 1000.123456e6; // USDC has 6 decimals
        uint256 equivalentUSDEAmount = 1000.123456e18; // USDE has 18 decimals (same USD value)

        // Cast vault to PublicViewsVault to access the public conversion functions
        PublicViewsVault publicVault = PublicViewsVault(payable(address(vault)));

        // Convert USDC to shares
        (uint256 sharesFromUSDC, uint256 baseAssetsFromUSDC) =
            publicVault.convertToSharesForAsset(MC.USDC, assetsAmount, Math.Rounding.Floor);

        // Convert USDE to shares
        (uint256 sharesFromUSDE, uint256 baseAssetsFromUSDE) =
            publicVault.convertToSharesForAsset(MC.USDE, equivalentUSDEAmount, Math.Rounding.Floor);

        // Both should result in the same number of shares since they represent the same USD value
        assertEq(sharesFromUSDC, sharesFromUSDE, "Shares from USDC and USDE should be equal");

        // Both should result in the same base assets (in 6 decimals)
        assertEq(baseAssetsFromUSDC, baseAssetsFromUSDE, "Base assets from USDC and USDE should be equal");

        // Verify that base assets are correctly calculated (should match the input values)
        assertEq(baseAssetsFromUSDC, assetsAmount * 1e12, "Base assets from USDC should match input amount");
        assertEq(baseAssetsFromUSDE, assetsAmount * 1e12, "Base assets from USDE should match input amount");

        {
            // Verify the reverse conversion for USDC
            (uint256 assetsBackUSDC, uint256 baseAssetsBackUSDC) =
                publicVault.convertToAssetsForAsset(MC.USDC, sharesFromUSDC, Math.Rounding.Floor);

            // Verify the reverse conversion for USDE
            (uint256 assetsBackUSDE, uint256 baseAssetsBackUSDE) =
                publicVault.convertToAssetsForAsset(MC.USDE, sharesFromUSDE, Math.Rounding.Floor);

            // Check that we get back the original amounts
            assertEq(assetsBackUSDC, assetsAmount, "Reverse conversion for USDC failed");
            assertEq(assetsBackUSDE, equivalentUSDEAmount, "Reverse conversion for USDE failed");
            assertEq(baseAssetsBackUSDC, baseAssetsBackUSDE, "Base assets from reverse conversion should be equal");
        }

        {
            // Demonstrate the decimals imprecision
            // Direct conversion from asset to base
            uint256 usdcToBase = publicVault.convertAssetToBase(MC.USDC, assetsAmount);
            uint256 usdeToBase = publicVault.convertAssetToBase(MC.USDE, equivalentUSDEAmount);

            assertEq(usdcToBase, usdeToBase, "Direct conversion to base should yield same result");
        }

        // Direct conversion from base to asset
        uint256 baseToUSDC = publicVault.convertBaseToAsset(MC.USDC, baseAssetsFromUSDC);
        uint256 baseToUSDE = publicVault.convertBaseToAsset(MC.USDE, baseAssetsFromUSDE);

        assertEq(baseToUSDC, assetsAmount, "Base to USDC conversion should match original amount");
        assertEq(baseToUSDE, equivalentUSDEAmount, "Base to USDE conversion should match original amount");

        // Demonstrate that the ratio between USDE and USDC is 10^12 (difference in decimals)
        assertEq(baseToUSDE / baseToUSDC, 1e12, "USDE to USDC ratio should be 10^12");
    }

    function test_Vault_depositAsset_USDE_thenDepositToSUSDE() public {
        uint256 depositAmount = 1_000_000_000e18; // USDE has 18 decimals

        // Give Alice USDE using MockERC20 mint
        vm.prank(alice);
        MockERC20(MC.USDE).mint(depositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMinted = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        // Process accounting to update vault state
        vault.processAccounting();

        // Check initial state after deposit
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), depositAmount, "Vault did not receive USDE");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");
        uint256 initialTotalBaseAssets = vault.totalBaseAssets();
        assertEq(initialTotalBaseAssets, depositAmount, "Initial total assets incorrect");

        assertEq(vault.totalAssets(), depositAmount / 1e12, "Total assets should equal the deposited amount");

        // Execute the processor rule to deposit USDE to SUSDE
        address[] memory targets = new address[](2);
        targets[0] = MC.USDE;
        targets[1] = MC.SUSDE;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        uint256 investedAmount = depositAmount / 2;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.SUSDE, investedAmount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", investedAmount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Process accounting to update vault state
        vault.processAccounting();

        // Verify USDE is now in SUSDE
        assertEq(
            IERC20(MC.USDE).balanceOf(address(vault)), depositAmount - investedAmount, "Vault should have no USDE left"
        );
        assertGt(IERC20(MC.SUSDE).balanceOf(address(vault)), 0, "Vault should have SUSDE tokens");

        // Total assets should remain the same since we just moved from one asset to another of same value
        uint256 finalTotaBaseAssets = vault.totalBaseAssets();
        assertApproxEqAbs(
            finalTotaBaseAssets,
            initialTotalBaseAssets,
            1,
            "Total assets should remain the same after depositing to SUSDE"
        );

        // Shares should remain unchanged
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice's shares should remain unchanged");
    }

    function test_Vault_depositAsset_USDE_with_rewards() public {
        // Initial deposit
        uint256 depositAmount = 1000_000e18;

        // Give Alice USDE by minting
        vm.startPrank(alice);
        MockERC20(MC.USDE).mint(depositAmount);
        vm.stopPrank();

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMinted = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

        // Simulate USDE rewards by having a rewarder send USDE to the vault
        uint256 rewardAmount = 100e18; // 100 USDE (18 decimals)
        {
            address rewarder = address(0xBEEF);
            vm.startPrank(rewarder);
            MockERC20(MC.USDE).mint(rewardAmount);
            IERC20(MC.USDE).transfer(address(vault), rewardAmount);
            vm.stopPrank();
        }

        // Process accounting to update vault state with rewards
        vault.processAccounting();

        // Record state before processor
        uint256 preTotalAssets = vault.totalAssets();
        uint256 aliceAssetsBeforeProcessor = vault.convertToAssets(sharesMinted);

        // Calculate total USDE in vault (original deposit + rewards)
        uint256 totalUsde = depositAmount + rewardAmount;

        // Execute the processor rule to deposit USDE to SUSDE
        address[] memory targets = new address[](2);
        targets[0] = MC.USDE;
        targets[1] = MC.SUSDE;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.SUSDE, totalUsde);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", totalUsde, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Process accounting to update vault state
        vault.processAccounting();

        // Verify USDE is now in SUSDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), 0, "Vault should have no USDE left");
        assertGt(IERC20(MC.SUSDE).balanceOf(address(vault)), 0, "Vault should have SUSDE tokens");

        // Total assets should remain the same after processor
        uint256 finalTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            finalTotalAssets, preTotalAssets, 2, "Total assets should remain the same after depositing to SUSDE"
        );

        // Alice's assets value should remain the same after processor
        uint256 aliceAssetsAfterProcessor = vault.convertToAssets(sharesMinted);
        assertApproxEqAbs(
            aliceAssetsAfterProcessor,
            aliceAssetsBeforeProcessor,
            2,
            "Alice's asset value should remain the same after processor"
        );
    }

    function test_Vault_deposit_1_wei() public {
        // Give Alice 1 wei USDC
        deal(MC.USDC, alice, 1);

        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1);

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Deposit 1 wei USDC
        vm.startPrank(alice);
        uint256 sharesMinted = vault.deposit(1, alice);
        vm.stopPrank();

        // It should mint 1e12 shares (because USDC is 6 decimals, and shares are 18 decimals)
        assertEq(sharesMinted, 1e12, "Incorrect shares minted for 1 wei deposit");

        // Alice should have 0 USDC and sharesMinted shares
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC not deducted");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct shares");

        // Vault should have 1 USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 1, "Vault did not receive 1 USDC");

        // Total assets/storage should reflect the deposit
        assertEq(vault.totalAssets(), 1, "totalAssets should be 1");
        assertEq(vault.totalBaseAssets(), 1e12, "totalBaseAssets should be 1e12");

        // Conversion rate for 1e18 shares should stay the same after 1 wei deposit
        uint256 afterRate = vault.convertToAssets(1e18);
        assertEq(initialRate, afterRate, "Conversion rate changed after 1 wei deposit");
    }

    function test_Vault_deposit_1_wei_USDT() public {
        // Give Alice 1 wei USDT
        deal(MC.USDT, alice, 1);

        vm.prank(alice);
        IERC20(MC.USDT).approve(address(vault), 1);

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Deposit 1 wei USDT
        vm.startPrank(alice);
        uint256 sharesMinted = vault.depositAsset(MC.USDT, 1, alice);
        vm.stopPrank();

        // It should mint 1e12 shares (because USDT is 6 decimals, and shares are 18 decimals)
        assertEq(sharesMinted, 1e12, "Incorrect shares minted for 1 wei deposit");

        // Alice should have 0 USDT and sharesMinted shares
        assertEq(IERC20(MC.USDT).balanceOf(alice), 0, "Alice's USDT not deducted");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct shares");

        // Vault should have 1 USDT
        assertEq(IERC20(MC.USDT).balanceOf(address(vault)), 1, "Vault did not receive 1 USDT");

        // Total assets/storage should reflect the deposit
        assertEq(vault.totalAssets(), 1, "totalAssets should be 1");
        assertEq(vault.totalBaseAssets(), 1e12, "totalBaseAssets should be 1e12");

        // Conversion rate for 1e18 shares should stay the same after 1 wei deposit
        uint256 afterRate = vault.convertToAssets(1e18);
        assertEq(initialRate, afterRate, "Conversion rate changed after 1 wei deposit");
    }

    function test_Vault_deposit_zero_wei_USDC() public {
        // Give Alice 0 USDC
        deal(MC.USDC, alice, 0);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), 0);

        uint256 sharesMinted = vault.depositAsset(MC.USDC, 0, alice);
        vm.stopPrank();

        assertEq(sharesMinted, 0, "Should mint 0 shares for 0 USDC deposit");
        assertEq(vault.balanceOf(alice), 0, "Alice's shares should stay 0");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault USDC should stay 0");
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC should stay 0");
        assertEq(vault.totalAssets(), 0, "Vault totalAssets should stay 0");
        assertEq(vault.totalBaseAssets(), 0, "Vault totalBaseAssets should stay 0");
    }

    function test_Vault_deposit_zero_wei_USDT() public {
        // Give Alice 0 USDT
        deal(MC.USDT, alice, 0);

        vm.startPrank(alice);
        IERC20(MC.USDT).approve(address(vault), 0);

        uint256 sharesMinted = vault.depositAsset(MC.USDT, 0, alice);
        vm.stopPrank();

        assertEq(sharesMinted, 0, "Should mint 0 shares for 0 USDT deposit");
        assertEq(vault.balanceOf(alice), 0, "Alice's shares should stay 0");
        assertEq(IERC20(MC.USDT).balanceOf(address(vault)), 0, "Vault USDT should stay 0");
        assertEq(IERC20(MC.USDT).balanceOf(alice), 0, "Alice's USDT should stay 0");
        assertEq(vault.totalAssets(), 0, "Vault totalAssets should stay 0");
        assertEq(vault.totalBaseAssets(), 0, "Vault totalBaseAssets should stay 0");
    }
}
