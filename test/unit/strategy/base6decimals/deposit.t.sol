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
import {console} from "lib/forge-std/src/console.sol";

contract BaseStrategy6DecimalsBaseDepositUnitTest is Test, MainnetActors, Etches {
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

        // Set up approval rule for USDE to SUSDE
        vm.startPrank(PROCESSOR_MANAGER);
        SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(MC.USDE, MC.SUSDE);
        vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
        SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(MC.SUSDE, address(vault));
        vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);
        vm.stopPrank();
    }

    function test_Strategy_initial_deposit_success(uint256 depositAmount) public {
        // Bound deposit amount between 10 and 100k USDC (6 decimals)
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 * 1e6) return;

        vm.prank(ASSET_MANAGER);

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

    function test_Strategy_initial_mint_success() public {
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
}
