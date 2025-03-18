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

contract Vault6DecimalsBaseDepositUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 200_000_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupBase6DecimalsVault();
        (vault, weth) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        // Set up approval rule for USDE to SUSDE
        vm.startPrank(PROCESSOR_MANAGER);
        SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(MC.USDE, MC.SUSDE);
        vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
        SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(MC.SUSDE, address(vault));
        vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);
        vm.stopPrank();
    }

    function test_Vault_initial_deposit_success(uint256 depositAmount, bool alwaysComputeTotalAssets) public {
        // Bound deposit amount between 10 and 100k USDC (6 decimals)
        if (depositAmount < 10) return;
        if (depositAmount > 100_000 * 1e6) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice USDC
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC
        uint256 sharesMinted = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

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

        // Check that shares minted is depositAmount * 1e12 (converting from 6 to 18 decimals)
        assertEq(sharesMinted, depositAmount * 1e12, "Incorrect number of shares minted");
        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function test_Vault_initial_mint_success() public {
        uint256 sharesToMint = 1000e18; // 1000 vault shares with 18 decimals
        bool alwaysComputeTotalAssets = true;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Give Alice USDC
        deal(MC.USDC, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Mint shares
        uint256 assetsDeposited = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        // Check that assets were deposited
        assertGt(assetsDeposited, 0, "No assets were deposited");

        // Check that the vault received the USDC
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), assetsDeposited, "Vault did not receive USDC");

        // Check that Alice's USDC balance decreased
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            INITIAL_BALANCE - assetsDeposited,
            "Alice's balance did not decrease correctly"
        );

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesToMint, "Alice did not receive the correct amount of shares");

        // Check that assets deposited is sharesToMint / 1e12 (converting from 18 to 6 decimals)
        assertEq(assetsDeposited, sharesToMint / 1e12, "Incorrect amount of assets deposited");

        // Check that total assets increased
        assertEq(vault.totalAssets(), assetsDeposited, "Total assets did not increase correctly");
    }

    function testFuzz_Vault_initial_depositAsset_USDE_success(uint256 depositAmount) public {
        // Assume reasonable deposit amount to avoid overflow and unrealistic values
        vm.assume(depositAmount > 1e12 && depositAmount <= 1_000_000_000e18);

        // Give Alice USDE
        deal(MC.USDE, alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMinted = vault.depositAsset(MC.USDE, depositAmount, alice);
        vm.stopPrank();

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
        assertEq(vault.totalAssets(), depositAmount / 1e12, "Total assets did not increase correctly");
    }

    function test_Vault_convertToAssetsForAsset_USDE_beforeDeposit() public {
        uint256 sharesAmount = 1000e18;

        // Cast vault to PublicViewsVault to access the public conversion functions
        PublicViewsVault publicVault = PublicViewsVault(payable(address(vault)));

        // Test conversion before any deposits are made
        (uint256 assets, uint256 baseAssets) =
            publicVault.convertToAssetsForAsset(MC.USDE, sharesAmount, Math.Rounding.Floor);

        // Since USDE has 18 decimals but is valued at 1 USD, the assets should be equal to shares
        // and baseAssets should be shares / 1e12 (converting from 18 to 6 decimals for USD value)
        assertEq(assets, sharesAmount, "Incorrect assets conversion");
        assertEq(baseAssets, sharesAmount / 1e12, "Incorrect baseAssets conversion");

        // Verify the reverse conversion as well
        (uint256 sharesBack, uint256 baseAssetsBack) =
            publicVault.convertToSharesForAsset(MC.USDE, assets, Math.Rounding.Floor);

        assertEq(sharesBack, sharesAmount, "Reverse conversion to shares failed");
        assertEq(baseAssetsBack, baseAssets, "Reverse conversion to baseAssets failed");

        // Test direct conversion functions
        uint256 convertedBaseAssets = publicVault.convertAssetToBase(MC.USDE, sharesAmount);
        assertEq(convertedBaseAssets, sharesAmount / 1e12, "Direct asset to base conversion failed");

        uint256 convertedAssets = publicVault.convertBaseToAsset(MC.USDE, convertedBaseAssets);
        assertEq(convertedAssets, sharesAmount, "Direct base to asset conversion failed");
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

        // Check initial state after deposit
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), depositAmount, "Vault did not receive USDE");
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");
        uint256 initialTotalAssets = vault.totalAssets();
        assertEq(initialTotalAssets, depositAmount / 1e12, "Initial total assets incorrect");

        // Execute the processor rule to deposit USDE to SUSDE
        address[] memory targets = new address[](2);
        targets[0] = MC.USDE;
        targets[1] = MC.SUSDE;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.SUSDE, depositAmount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Process accounting to update vault state
        vault.processAccounting();

        // Verify USDE is now in SUSDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), 0, "Vault should have no USDE left");
        assertGt(IERC20(MC.SUSDE).balanceOf(address(vault)), 0, "Vault should have SUSDE tokens");

        // Total assets should remain the same since we just moved from one asset to another of same value
        uint256 finalTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            finalTotalAssets, initialTotalAssets, 1, "Total assets should remain the same after depositing to SUSDE"
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
            finalTotalAssets, preTotalAssets, 1, "Total assets should remain the same after depositing to SUSDE"
        );

        // Alice's assets value should remain the same after processor
        uint256 aliceAssetsAfterProcessor = vault.convertToAssets(sharesMinted);
        assertApproxEqAbs(
            aliceAssetsAfterProcessor,
            aliceAssetsBeforeProcessor,
            1,
            "Alice's asset value should remain the same after processor"
        );
    }
}
