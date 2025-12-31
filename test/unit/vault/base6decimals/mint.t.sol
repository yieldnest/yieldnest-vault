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

    function test_Vault_initial_mint_success() public {
        uint256 sharesToMint = 1000e18; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Approve vault to spend Alice's wUSDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Check that assets were deposited
        assertGt(assetsDeposited, 0, "No assets were deposited");

        // Check that the vault received the wUSDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive wUSDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");

        // Check that assets deposited is sharesToMint (since wUSDC has 18 decimals)
        assertEq(assetsDeposited * 1e12, sharesToMint, "Incorrect amount of assets deposited");

        // Check that total assets increased
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited * 1e12, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_mint_success(uint256 sharesToMint) public {
        // Bound sharesToMint to ensure it's a reasonably small number (like the deposit fuzz)
        // 1e12 shares = 1 USDC required to mint (since 1 share = 1e18, 1 USDC = 1e6)
        // Let's set lower bound to 1e12 (1 USDC) and upper bound to 100_000 * 1e18 (100k vault shares)
        vm.assume(sharesToMint >= 1e12 && sharesToMint <= 100_000 * 1e18);

        bool alwaysComputeTotalAssets = true;
        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice enough USDC to cover minting the fuzzed shares
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Record initial rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);

        vm.stopPrank();

        // Check that some assets were deposited and the shares minted are not zero
        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertGt(sharesToMint, 0, "No shares were minted");

        // Check that the vault received the correct amount of USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive USDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");

        // VERY IMPORTANT: the shares minted are below the value of the assets deposited always.
        assertApproxEqAbs(assetsDeposited, sharesToMint / 1e12, 1, "Incorrect amount of assets deposited");
        assertLe(
            sharesToMint / 1e12, assetsDeposited, "Assets deposited should be less than or equal to sharesToMint / 1e12"
        );

        // Check that total assets increased correctly
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited * 1e12, "Total base assets did not increase correctly");

        // Total supply should match what was minted
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch");

        // Conversion rate should be clamped between 1 and 2x the initial rate since share minting can be 2e12 - 1.
        uint256 afterRate = vault.convertToAssets(1e18);
        assertLt(afterRate, 2 * initialRate, "Vault conversion rate changed after mint");
        assertGe(afterRate, initialRate, "Vault conversion rate should increase after mint");
    }

    function test_Vault_initial_low_mint_success() public {
        uint256 sharesToMint = 1e11; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Get rate before mint
        uint256 initialRate = vault.convertToAssets(1e18);

        // Approve vault to spend Alice's wUSDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Check that the vault received the wUSDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive wUSDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");

        // Check that assets deposited is sharesToMint (since wUSDC has 18 decimals)
        // assertEq(assetsDeposited * 1e12, sharesToMint, "Incorrect amount of assets deposited");

        // Check that total assets increased
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
        assertEq(vault.totalBaseAssets(), assetsDeposited * 1e12, "Total assets did not increase correctly");

        assertEq(vault.totalSupply(), sharesToMint, "Convert to shares failed");

        uint256 finalRate = vault.convertToAssets(1e18);

        assertGt(finalRate, initialRate, "Vault conversion rate should increase after mint");

        // rate increases by 10x - 1 wei, due to rounding up.
        // Note this only happens if the boostrap mint call is 1e12 -1 shares or less.abi
        assertEq(finalRate, initialRate * 10 - 1, "Vault conversion rate should be 10x the initial rate - 1");
    }

    function testFuzz_Vault_initial_low_mint_success(uint64 fuzzSharesToMint) public {
        // Cap sharesToMint to [1, 1e12)
        uint256 sharesToMint = bound(uint256(fuzzSharesToMint), 1, 1e12 - 1); // range: [1, 1e12 - 1]

        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice enough USDC to mint these shares, using previewMint for calculation
        uint256 usdcNeeded = vault.previewMint(sharesToMint);
        deal(MC.USDC, alice, usdcNeeded);

        // Get rate before mint
        uint256 initialRate = vault.convertToAssets(1e18);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Check that at least some assets were deposited and Alice got the shares
        assertGt(assetsDeposited, 0, "No assets were deposited");
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive correct shares");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch on fuzz mint");

        // Vault should have received the assets deposited
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive correct USDC");

        // Alice's USDC balance decreased as expected
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            usdcNeeded - assetsDeposited,
            "Alice balance did not decrease by assetsDeposited"
        );

        // Check totalAssets and totalBaseAssets
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly (fuzz)");
        assertEq(vault.totalBaseAssets(), assetsDeposited * 1e12, "TotalBaseAssets incorrect (fuzz)");

        // Conversion rate should stay the same or increase
        uint256 afterRate = vault.convertToAssets(1e18);
        assertGe(afterRate, initialRate, "Vault conversion rate should increase after fuzz mint");
        // Rate can increase by up to 1e12x the initial rate, due to rounding up.
        assertLe(
            afterRate,
            initialRate * 1e12,
            "Vault conversion rate should be less than or equal to 1e12x the initial rate"
        );
    }

    function test_Vault_initial_low_deposit_success() public {
        uint256 sharesToMint = 1e12; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Record initial rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Deposit USDC
        uint256 sharesMinted = vault.deposit(sharesToMint / 1e12, alice); // Convert sharesToMint to USDC 6 decimals
        vm.stopPrank();

        // Assumptions and checks
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check vault balances and state
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive correct amount of shares");
        assertEq(vault.totalSupply(), sharesMinted, "Total supply mismatch");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), sharesToMint / 1e12, "Vault did not receive correct USDC");
        assertEq(vault.totalAssets(), sharesToMint / 1e12, "Vault totalAssets incorrect");
        assertEq(vault.totalBaseAssets(), sharesToMint, "Vault totalBaseAssets incorrect");

        // Assert the conversion rate stayed the same
        uint256 afterRate = vault.convertToAssets(1e18);
        assertEq(afterRate, initialRate, "Vault conversion rate changed after low deposit");
    }

    function test_Vault_second_low_deposit_success() public {
        uint256 boostrapShares = 100_000e18; // 100,000 vault shares (18 decimals)
        uint256 sharesToMint = 1e12;
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC for bootstrap + second deposit
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Record initial rate
        uint256 initialRate = vault.convertToAssets(1e18);

        // Alice does a first bootstrap deposit
        uint256 bootstrapDepositAmount = boostrapShares / 1e12; // 1000 USDC (6 decimals)
        uint256 bootstrapSharesMinted = vault.deposit(bootstrapDepositAmount, alice);

        // Record rate after first deposit
        uint256 afterBootstrapRate = vault.convertToAssets(1e18);

        // Alice does a second small deposit
        uint256 secondDepositAmount = 1;
        uint256 sharesMinted = vault.deposit(secondDepositAmount, alice);

        assertEq(sharesMinted, sharesToMint, "Shares minted should be equivalent to the second deposit amount");

        vm.stopPrank();

        // Check vault balances and state
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

        // Check that the conversion rate did not change substantially between the two deposits
        uint256 finalRate = vault.convertToAssets(1e18);
        assertEq(afterBootstrapRate, initialRate, "Vault conversion rate changed after bootstrap deposit");
        assertEq(finalRate, afterBootstrapRate, "Vault conversion rate changed after second deposit");
    }

    function test_Vault_initial_min_usdc_mint_success() public {
        uint256 sharesToMint = 1e12; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Record initial rate
        uint256 initialRate = vault.convertToAssets(1e18);

        vault.mint(sharesToMint, alice); // Convert sharesToMint to USDC 6 decimals

        vm.stopPrank();

        // Assumptions and checks
        assertGt(sharesToMint, 0, "No shares were minted");

        // Check vault balances and state
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive correct amount of shares");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply mismatch");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 1 wei, "Vault did not receive correct USDC");
        assertEq(vault.totalAssets(), 1 wei, "Vault totalAssets incorrect");
        assertEq(vault.totalBaseAssets(), sharesToMint, "Vault totalBaseAssets incorrect");

        // Assert the conversion rate stayed the same
        uint256 afterRate = vault.convertToAssets(1e18);
        assertEq(afterRate, initialRate, "Vault conversion rate changed after low deposit");
    }

    function test_Vault_second_low_mint_success() public {
        uint256 sharesToMint = 1e11; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        {
            // Give Alice USDC
            deal(MC.USDC, alice, INITIAL_BALANCE);
        }

        // Get rate before mint
        uint256 initialRate = vault.convertToAssets(1e18);

        uint256 bootstrapDeposit = 100_000e6;
        uint256 boostrapShares;
        {
            // Do a deposit call with alice for 1000 ether before mint
            vm.startPrank(alice);
            IERC20(MC.USDC).approve(address(vault), type(uint256).max);
            boostrapShares = vault.deposit(bootstrapDeposit, alice);
            vm.stopPrank();
        }

        // Approve vault to spend Alice's wUSDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Check that assets were deposited
        assertGt(assetsDeposited, 0, "No assets were deposited");

        // Check that the vault received the wUSDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited + bootstrapDeposit, "Vault did not receive wUSDC"
        );

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited - bootstrapDeposit,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(
            vault.balanceOf(alice), sharesToMint + boostrapShares, "Alice did not receive the correct amount of shares"
        );

        // Check that assets deposited is sharesToMint (since wUSDC has 18 decimals)
        // assertEq(assetsDeposited * 1e12, sharesToMint, "Incorrect amount of assets deposited");

        // Check that total assets increased
        assertEq(vault.totalAssets(), assetsDeposited + bootstrapDeposit, "Total assets did not increase correctly");
        assertEq(
            vault.totalBaseAssets(),
            (assetsDeposited + bootstrapDeposit) * 1e12,
            "Total assets did not increase correctly"
        );

        assertEq(vault.totalSupply(), sharesToMint + boostrapShares, "Total supply mismatch");

        assertEq(
            assetsDeposited,
            vault.convertToAssets(sharesToMint * 10),
            "Assets deposited should be equivalent to minting 10x the shares"
        );

        assertEq(vault.convertToAssets(1e18), initialRate, "Rate stays the same");
    }

    function test_Vault_mint_zero_shares_zero_effect() public {
        uint256 sharesToMint = 0;
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice USDC
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        uint256 assetsDeposited = vault.mint(sharesToMint, alice);

        vm.stopPrank();

        // Nothing should have changed
        assertEq(assetsDeposited, 0, "No assets should be deposited");
        assertEq(vault.balanceOf(alice), 0, "Alice should receive zero shares");
        assertEq(IERC20(MC.USDC).balanceOf(alice), INITIAL_BALANCE, "Alice's USDC balance should not change");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), 0, "Vault should not receive any USDC");
        assertEq(vault.totalAssets(), 0, "Vault total assets should remain 0");
        assertEq(vault.totalBaseAssets(), 0, "Vault total base assets should remain 0");
        assertEq(vault.totalSupply(), 0, "Vault total supply should remain 0");
    }
}
