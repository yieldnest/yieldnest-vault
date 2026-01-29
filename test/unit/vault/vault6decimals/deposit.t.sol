// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {Setup6DecimalsVault} from "test/unit/vault/vault6decimals/Setup6DecimalsVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "lib/forge-std/src/console.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {MainnetActors} from "script/Actors.sol";

contract Vault6DecimalsDepositUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 * 1e6; // For 6 decimals vault

    function setUp() public {
        Setup6DecimalsVault setupVault = new Setup6DecimalsVault();
        (vault,) = setupVault.setup();

        // Give Alice some ETH for potential fuzzing or EOA-interaction
        deal(alice, 1_000_000 ether); // ETH for native operations
    }

    function test_Vault_previewDeposit_0_wei() public {
        uint256 assets = 0;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, 0, "Preview deposit does not match expected shares");
    }

    function test_Vault_previewDeposit_1_wei() public {
        uint256 assets = 1;
        uint256 shares = vault.previewDeposit(assets);
        // For a 6 decimal vault, shares = assets * (1e18 / 1e6) = assets * 1e12
        assertEq(shares, 1, "Preview deposit does not match expected shares");
    }

    function test_Vault_initial_deposit_success(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        // Bound deposit amount between 10 and 100k USDC (6 decimals)
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 * 1e6) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice USDC
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1e6); // 1 share = 1e6 base units for 6 decimals

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.assume(sharesMinted > 0);

        // Check rate after deposit is the same as before
        uint256 afterRate = vault.convertToAssets(1e6);
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

        // For 6 decimals: shares minted should exactly equal depositAmount
        assertEq(sharesMinted, depositAmount, "Incorrect number of shares minted");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), depositAmount, "Total base assets did not increase correctly");
    }

    function testFuzz_Vault_initial_depositAsset_USDC_success(uint256 depositAmount) public {
        // Assume reasonable deposit amount to avoid overflow and unrealistic values
        vm.assume(depositAmount > 1e6 && depositAmount <= 1_000_000_000e6);

        // Give Alice USDC
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Record assets value before deposit
        uint256 assetsBeforeDeposit = vault.convertToAssets(1e6);

        // Deposit USDC using depositAsset
        uint256 sharesMinted = vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();

        // Verify convertToAssets stayed the same for existing shares
        uint256 assetsAfterDeposit = vault.convertToAssets(1e6);
        assertEq(assetsBeforeDeposit, assetsAfterDeposit, "convertToAssets should remain the same for existing shares");

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault did not receive USDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - depositAmount,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");
        // For 6 decimals vault and 6 decimals USDC: shares = depositAmount
        assertEq(sharesMinted, depositAmount, "Incorrect number of shares minted");

        // Check that total assets increased by the USDC value
        assertEq(vault.totalBaseAssets(), depositAmount, "Total base assets did not increase correctly");
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_USDC_deposit_then_depositAsset_USDT_success(
        uint256 usdtDepositAmount,
        uint256 usdcDepositAmount
    ) public {
        // Assume reasonable deposit amounts to avoid overflow and unrealistic values
        vm.assume(usdtDepositAmount > 1e6 && usdtDepositAmount <= 1_000_000_000e6);
        vm.assume(usdcDepositAmount > 1e6 && usdcDepositAmount <= 1_000_000_000e6);

        // Give Alice an initial USDC balance
        deal(MC.USDC, alice, usdcDepositAmount);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Give Alice USDT
        deal(MC.USDT, alice, usdtDepositAmount);

        // Approve vault to spend Alice's USDT
        vm.startPrank(alice);
        IERC20(MC.USDT).approve(address(vault), type(uint256).max);

        // Deposit USDT using depositAsset
        uint256 sharesMintedFromUSDT = vault.depositAsset(MC.USDT, usdtDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDT
        assertEq(IERC20(MC.USDT).balanceOf(address(vault)), usdtDepositAmount, "Vault did not receive USDT");

        // Check that Alice's USDT balance decreased
        assertEq(IERC20(MC.USDT).balanceOf(alice), 0, "Alice's USDT balance did not decrease correctly");

        // Check that shares minted is correct
        assertEq(
            vault.balanceOf(alice),
            sharesMintedFromUSDC + sharesMintedFromUSDT,
            "Alice did not receive the correct amount of shares from USDT deposit"
        );

        // Both USDC and USDT are 6 decimals, so for both: shares = respective depositAmount
        assertEq(sharesMintedFromUSDT, usdtDepositAmount, "Incorrect number of shares minted from USDT");
        assertEq(sharesMintedFromUSDC, usdcDepositAmount, "Incorrect number of shares minted from USDC");

        // Check that total assets increased by the sum of the USD values
        uint256 totalDeposit = usdtDepositAmount + usdcDepositAmount;
        assertEq(vault.totalBaseAssets(), totalDeposit, "Total base assets did not increase correctly");
        assertEq(vault.totalAssets(), totalDeposit, "Total assets did not increase correctly");
    }

    function test_Vault_convertToAssetsForAsset_USDC_beforeDeposit() public view {
        uint256 sharesAmount = 1000e6; // 6 decimals (e.g., 1,000.000000)

        // Cast vault to PublicViewsVault to access the public conversion functions
        PublicViewsVault publicVault = PublicViewsVault(payable(address(vault)));

        // Test conversion before any deposits are made
        (uint256 assets, uint256 baseAssets) =
            publicVault.convertToAssetsForAsset(MC.USDC, sharesAmount, Math.Rounding.Floor);

        // Both assets and baseAssets should match for 6 decimal vault
        assertEq(assets, sharesAmount, "Incorrect assets conversion (USDC/6dec vault)");
        assertEq(baseAssets, sharesAmount, "Incorrect baseAssets conversion (should be shares)");

        // Verify the reverse conversion as well
        (uint256 sharesBack, uint256 baseAssetsBack) =
            publicVault.convertToSharesForAsset(MC.USDC, assets, Math.Rounding.Floor);

        assertEq(sharesBack, sharesAmount, "Reverse conversion to shares failed");
        assertEq(baseAssetsBack, sharesAmount, "Reverse conversion to baseAssets failed");

        // Test direct conversion functions
        uint256 convertedBaseAssets = publicVault.convertAssetToBase(MC.USDC, assets);
        assertEq(convertedBaseAssets, assets, "Direct asset to base conversion failed (USDC/6dec vault)");

        uint256 convertedAssets = publicVault.convertBaseToAsset(MC.USDC, convertedBaseAssets);
        assertEq(convertedAssets, assets, "Direct base to asset conversion failed (USDC/6dec vault)");
    }

    function test_Vault_convertToSharesForAsset_USDC_vs_USDT() public view {
        uint256 assetsAmount = 1000.123456e6; // USDC/USDT has 6 decimals

        // Cast vault to PublicViewsVault to access the public conversion functions
        PublicViewsVault publicVault = PublicViewsVault(payable(address(vault)));

        // Convert USDC to shares
        (uint256 sharesFromUSDC, uint256 baseAssetsFromUSDC) =
            publicVault.convertToSharesForAsset(MC.USDC, assetsAmount, Math.Rounding.Floor);

        // Convert USDT to shares
        (uint256 sharesFromUSDT, uint256 baseAssetsFromUSDT) =
            publicVault.convertToSharesForAsset(MC.USDT, assetsAmount, Math.Rounding.Floor);

        // Both should result in the same number of shares since they're the same decimals and value
        assertEq(sharesFromUSDC, sharesFromUSDT, "Shares from USDC and USDT should be equal");
        assertEq(baseAssetsFromUSDC, baseAssetsFromUSDT, "Base assets from USDC and USDT should be equal");

        // Both shares should be assetsAmount
        assertEq(baseAssetsFromUSDC, assetsAmount, "Base assets from USDC should match input amount");
        assertEq(baseAssetsFromUSDT, assetsAmount, "Base assets from USDT should match input amount");

        // Reverse conversion for USDC and USDT
        (uint256 assetsBackUSDC, uint256 baseAssetsBackUSDC) =
            publicVault.convertToAssetsForAsset(MC.USDC, sharesFromUSDC, Math.Rounding.Floor);
        (uint256 assetsBackUSDT, uint256 baseAssetsBackUSDT) =
            publicVault.convertToAssetsForAsset(MC.USDT, sharesFromUSDT, Math.Rounding.Floor);

        assertEq(assetsBackUSDC, assetsAmount, "Reverse conversion for USDC failed");
        assertEq(assetsBackUSDT, assetsAmount, "Reverse conversion for USDT failed");
        assertEq(baseAssetsBackUSDC, baseAssetsBackUSDT, "Base assets from reverse conversion should be equal");

        // Direct conversion
        uint256 usdcToBase = publicVault.convertAssetToBase(MC.USDC, assetsAmount);
        uint256 usdtToBase = publicVault.convertAssetToBase(MC.USDT, assetsAmount);

        assertEq(usdcToBase, usdtToBase, "Direct conversion to base should yield same result");

        uint256 baseToUSDC = publicVault.convertBaseToAsset(MC.USDC, baseAssetsFromUSDC);
        uint256 baseToUSDT = publicVault.convertBaseToAsset(MC.USDT, baseAssetsFromUSDT);

        assertEq(baseToUSDC, assetsAmount, "Base to USDC conversion should match original amount");
        assertEq(baseToUSDT, assetsAmount, "Base to USDT conversion should match original amount");
    }

    function test_Vault_deposit_1_wei() public {
        // Give Alice 1 wei USDC
        deal(MC.USDC, alice, 1);

        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1);

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1);

        // Deposit 1 wei USDC
        vm.startPrank(alice);
        uint256 sharesMinted = vault.deposit(1, alice);
        vm.stopPrank();

        // It should mint 1 share (because vault, share, USDC all are 6 decimals)
        assertEq(sharesMinted, 1, "Incorrect shares minted for 1 wei deposit");

        // Alice should have 0 USDC and sharesMinted shares
        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice's USDC not deducted");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct shares");

        // Vault should have 1 USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 1, "Vault did not receive 1 USDC");

        // Total assets/storage should reflect the deposit
        assertEq(vault.totalAssets(), 1, "totalAssets should be 1");
        assertEq(vault.totalBaseAssets(), 1, "totalBaseAssets should be 1");

        // Conversion rate for 1 share should stay the same after 1 wei deposit
        uint256 afterRate = vault.convertToAssets(1);
        assertEq(initialRate, afterRate, "Conversion rate changed after 1 wei deposit");
    }

    function test_Vault_deposit_1_wei_USDT() public {
        // Give Alice 1 wei USDT
        deal(MC.USDT, alice, 1);

        vm.prank(alice);
        IERC20(MC.USDT).approve(address(vault), 1);

        // Check initial conversion rate
        uint256 initialRate = vault.convertToAssets(1);

        // Deposit 1 wei USDT
        vm.startPrank(alice);
        uint256 sharesMinted = vault.depositAsset(MC.USDT, 1, alice);
        vm.stopPrank();

        // Should mint 1 share for 1 USDT
        assertEq(sharesMinted, 1, "Incorrect shares minted for 1 wei USDT deposit");

        // Alice should have 0 USDT and sharesMinted shares
        assertEq(IERC20(MC.USDT).balanceOf(alice), 0, "Alice's USDT not deducted");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct shares");

        // Vault should have 1 USDT
        assertEq(IERC20(MC.USDT).balanceOf(address(vault)), 1, "Vault did not receive 1 USDT");

        // Total assets/storage should reflect the deposit
        assertEq(vault.totalAssets(), 1, "totalAssets should be 1");
        assertEq(vault.totalBaseAssets(), 1, "totalBaseAssets should be 1");

        // Conversion rate for 1 share should stay the same after 1 wei deposit
        uint256 afterRate = vault.convertToAssets(1);
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
