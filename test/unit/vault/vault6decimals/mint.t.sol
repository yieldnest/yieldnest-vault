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
import {Setup6DecimalsVault} from "test/unit/vault/vault6decimals/Setup6DecimalsVault.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";

contract Vault6DecimalsMintUnitTest is Test, MainnetActors, Etches {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 * 1e6; // 6 decimals, e.g. USDC

    function setUp() public {
        Setup6DecimalsVault setupVault = new Setup6DecimalsVault();
        (vault,) = setupVault.setup();

        // Give Alice some tokens (as if 6 decimals)
        deal(alice, INITIAL_BALANCE);
    }

    function test_Vault_previewMint_1_wei() public {
        uint256 shares = 1;
        uint256 assets = vault.previewMint(shares);
        // with a 1:1 relationship at 6 decimals, 1 share => 1 asset
        assertEq(assets, 1, "Preview mint does not match expected assets");
    }

    function test_Vault_previewMint_1e6_minus_1() public {
        uint256 shares = 1e6 - 1;
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, 1e6 - 1, "Preview mint does not match expected assets");
    }

    function test_Vault_previewMint_1e6() public {
        uint256 shares = 1e6;
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, 1e6, "Preview mint does not match expected assets");
    }

    function test_Vault_initial_mint_success() public {
        uint256 sharesToMint = 1000e6; // 1000 shares for 6 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");
        // At 1:1, assetsDeposited == sharesToMint for 6 decimals
        assertEq(assetsDeposited, sharesToMint, "Incorrect amount of assets deposited");
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_mint_success(uint256 sharesToMint) public {
        vm.assume(sharesToMint >= 1 && sharesToMint <= 100_000 * 1e6);

        bool alwaysComputeTotalAssets = true;
        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 initialRate = vault.convertToAssets(1e6);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);

        vm.stopPrank();

        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertGt(sharesToMint, 0, "No shares were minted");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");
        // Expect assetsDeposited == sharesToMint for 6 decimals
        assertEq(assetsDeposited, sharesToMint, "Incorrect amount of assets deposited");
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited, "Total base assets did not increase correctly");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch");
        uint256 afterRate = vault.convertToAssets(1e6);
        assertEq(afterRate, initialRate, "Vault conversion rate shouldn't change on mint");
    }

    function test_Vault_initial_low_mint_success() public {
        uint256 sharesToMint = 1; // Smallest unit for 6 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        uint256 initialRate = vault.convertToAssets(1e6);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");
        assertEq(assetsDeposited, sharesToMint, "Incorrect amount of assets deposited");
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalSupply(), sharesToMint, "Convert to shares failed");

        uint256 finalRate = vault.convertToAssets(1e6);

        assertEq(finalRate, initialRate, "Vault conversion rate should not change after mint");
    }

    function testFuzz_Vault_initial_low_mint_success(uint64 fuzzSharesToMint) public {
        uint256 sharesToMint = bound(uint256(fuzzSharesToMint), 1, 1e6 - 1); // range: [1, 1e6 - 1]

        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 usdcNeeded = vault.previewMint(sharesToMint);
        deal(MC.USDC, alice, usdcNeeded);

        uint256 initialRate = vault.convertToAssets(1e6);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive correct shares");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch on fuzz mint");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive correct USDC");
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            usdcNeeded - assetsDeposited,
            "Alice balance did not decrease by assetsDeposited"
        );
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly (fuzz)");
        assertEq(vault.totalBaseAssets(), assetsDeposited, "TotalBaseAssets incorrect (fuzz)");

        uint256 afterRate = vault.convertToAssets(1e6);
        assertEq(afterRate, initialRate, "Vault conversion rate should not change on mint");
    }

    function test_Vault_initial_low_deposit_success() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 initialRate = vault.convertToAssets(1e6);

        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(sharesMinted, 0, "No shares were minted");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct amount of shares");
        assertEq(vault.totalSupply(), sharesMinted, "Total supply mismatch");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), depositAmount, "Vault did not receive correct USDC");
        assertEq(vault.totalAssets(), depositAmount, "Vault totalAssets incorrect");
        assertEq(vault.totalBaseAssets(), depositAmount, "Vault totalBaseAssets incorrect");

        uint256 afterRate = vault.convertToAssets(1e6);
        assertEq(afterRate, initialRate, "Vault conversion rate changed after low deposit");
    }

    function test_Vault_second_low_deposit_success() public {
        uint256 bootstrapShares = 100_000e6; // 100,000 shares (6 decimals)
        uint256 sharesToMint = 1e6; // 1 USDC worth at 6 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 initialRate = vault.convertToAssets(1e6);

        uint256 bootstrapDepositAmount = bootstrapShares; // 100_000 USDC (6 decimals)
        uint256 bootstrapSharesMinted = vault.deposit(bootstrapDepositAmount, alice);

        uint256 afterBootstrapRate = vault.convertToAssets(1e6);

        uint256 secondDepositAmount = 1;
        uint256 sharesMinted = vault.deposit(secondDepositAmount, alice);

        assertEq(sharesMinted, secondDepositAmount, "Shares minted should be equivalent to the second deposit amount");

        vm.stopPrank();

        assertEq(
            vault.balanceOf(alice),
            bootstrapSharesMinted + sharesMinted,
            "Alice did not receive correct amount of shares"
        );
        assertEq(vault.totalSupply(), bootstrapSharesMinted + sharesMinted, "Total supply mismatch");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            bootstrapDepositAmount + secondDepositAmount,
            "Vault did not receive correct USDC"
        );
        assertEq(vault.totalAssets(), bootstrapDepositAmount + secondDepositAmount, "Vault totalAssets incorrect");
        assertEq(vault.totalBaseAssets(), (bootstrapSharesMinted + sharesMinted), "Vault totalBaseAssets incorrect");

        uint256 finalRate = vault.convertToAssets(1e6);
        assertEq(afterBootstrapRate, initialRate, "Vault conversion rate changed after bootstrap deposit");
        assertEq(finalRate, afterBootstrapRate, "Vault conversion rate changed after second deposit");
    }

    function test_Vault6decimals_initial_min_usdc_mint_success() public {
        uint256 sharesToMint = 1e6; // 1 USDC worth of shares with 6 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 initialRate = vault.convertToAssets(1e6);

        vault.mint(sharesToMint, alice);

        vm.stopPrank();

        assertGt(sharesToMint, 0, "No shares were minted");
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive correct amount of shares");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch");

        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), sharesToMint, "Vault did not receive correct USDC");
        assertEq(vault.totalAssets(), sharesToMint, "Vault totalAssets incorrect");
        assertEq(vault.totalBaseAssets(), sharesToMint, "Vault totalBaseAssets incorrect");

        uint256 afterRate = vault.convertToAssets(1e6);
        assertEq(afterRate, initialRate, "Vault conversion rate changed after low deposit");
    }

    function test_Vault_second_low_mint_success() public {
        uint256 sharesToMint = 1; // Smallest unit for 6 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        uint256 initialRate = vault.convertToAssets(1e6);

        uint256 bootstrapDeposit = 100_000e6;
        uint256 boostrapShares;
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);
        boostrapShares = vault.deposit(bootstrapDeposit, alice);
        vm.stopPrank();

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited + bootstrapDeposit, "Vault did not receive USDC"
        );

        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited - bootstrapDeposit,
            "Alice's balance did not decrease correctly"
        );
        assertEq(
            vault.balanceOf(alice), sharesToMint + boostrapShares, "Alice did not receive the correct amount of shares"
        );
        assertEq(vault.totalAssets(), assetsDeposited + bootstrapDeposit, "Total assets did not increase correctly");
        assertEq(
            vault.totalBaseAssets(),
            (assetsDeposited + bootstrapDeposit),
            "Total base assets did not increase correctly"
        );
        assertEq(vault.totalSupply(), sharesToMint + boostrapShares, "Total supply mismatch");
        assertEq(vault.convertToAssets(1e6), initialRate, "Rate stays the same");
    }

    function test_Vault_mint_zero_shares_zero_effect() public {
        uint256 sharesToMint = 0;
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        deal(MC.USDC, alice, INITIAL_BALANCE);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);

        vm.stopPrank();

        assertEq(assetsDeposited, 0, "No assets should be deposited");
        assertEq(vault.balanceOf(alice), 0, "Alice should receive zero shares");
        assertEq(IERC20(MC.USDC).balanceOf(alice), INITIAL_BALANCE, "Alice's USDC balance should not change");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault should not receive any USDC");
        assertEq(vault.totalAssets(), 0, "Vault total assets should remain 0");
        assertEq(vault.totalBaseAssets(), 0, "Vault total base assets should remain 0");
        assertEq(vault.totalSupply(), 0, "Vault total supply should remain 0");
    }
}
