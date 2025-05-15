/* solhint-disable one-contract-per-file, gas-custom-errors */
// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {IERC20} from "src/Common.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {console} from "lib/forge-std/src/console.sol";

contract VaultSlashingUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;
    MockERC4626 public mockVault;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Create a mock ERC4626 vault with WETH as the underlying asset
        mockVault = new MockERC4626(ERC20(address(weth)), "Mock Vault", "mVault");

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        {
            // Add mockVault as an asset to the vault
            vm.prank(ASSET_MANAGER);
            vault.addAsset(address(mockVault), false);

            // Set METH rate to 1.2 ETH
            MockProvider(MC.PROVIDER).addERC4626(address(mockVault));
        }

        // Set up approval rule for WETH to mockVault
        vm.startPrank(PROCESSOR_MANAGER);

        // Create an allowlist with mockVault
        address[] memory allowList = new address[](2);
        allowList[0] = address(mockVault);
        allowList[1] = MC.BUFFER;

        // Set up approval rule for WETH
        SafeRules.RuleParams memory approvalRuleParams = BaseRules.getApprovalRule(address(weth), allowList);
        vault.setProcessorRule(approvalRuleParams.contractAddress, approvalRuleParams.funcSig, approvalRuleParams.rule);

        // Set up deposit rule for mockVault
        SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(address(mockVault), address(vault));
        vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);

        vm.stopPrank();
    }

    function test_deposit_WETH_And_Slash(uint256 depositAmount, uint256 slashFraction) public {
        // Bound the deposit amount to be reasonable but non-zero
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);

        // Bound the slash fraction between 0.1% and 99.9%
        slashFraction = bound(slashFraction, 1 wei, 1 ether);

        // Ensure Alice has enough balance
        vm.assume(depositAmount <= INITIAL_BALANCE);

        // Perform the deposit as Alice
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Allocate the deposited WETH to the mock buffer strategy
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(mockVault), depositAmount, PROCESSOR);

        // Verify the allocation was successful
        assertEq(weth.balanceOf(address(vault)), 0, "Vault should have transferred all WETH to mock buffer");
        assertEq(
            IERC20(address(mockVault)).balanceOf(address(vault)),
            depositAmount,
            "Mock buffer should have received the deposit amount"
        );

        // Store the total assets before slashing
        uint256 totalAssetsBeforeSlash = vault.totalAssets();

        // Use the slash function to simulate the loss
        mockVault.slash(slashFraction);

        // Get the balance of underlying assets in mockVault after slashing
        uint256 remainingAmount = IERC20(mockVault.asset()).balanceOf(address(mockVault));

        // Verify the slashing occurred
        uint256 vaultSharesValue = mockVault.convertToAssets(mockVault.balanceOf(address(vault)));
        assertEq(vaultSharesValue, remainingAmount, "Mock vault shares should be worth less after slashing");

        assertEq(
            vault.totalAssets(), totalAssetsBeforeSlash, "Total assets stay the same until processAccounting is called"
        );

        // Call processAccounting to update the vault's accounting
        vm.prank(PROCESSOR);
        vault.processAccounting();

        // Verify that total assets have been updated after processAccounting
        uint256 totalAssetsAfterAccounting = vault.totalAssets();

        assertLt(
            totalAssetsAfterAccounting,
            totalAssetsBeforeSlash,
            "Total assets should decrease after processAccounting due to slashing"
        );

        // Calculate expected assets after slashing
        uint256 expectedAssetsAfterSlash = depositAmount - (depositAmount * slashFraction / 1 ether);

        // Allow for small rounding errors due to decimal calculations
        assertApproxEqAbs(
            totalAssetsAfterAccounting,
            expectedAssetsAfterSlash,
            1,
            "Total assets should match the expected value after slashing"
        );
    }

    function test_deposit_WETH_And_Slash_And_Withdraw(
        uint256 depositAmount,
        uint256 bufferDepositAmount,
        uint256 slashFraction
    ) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        bufferDepositAmount = bound(bufferDepositAmount, depositAmount, 100_000 ether);
        slashFraction = bound(slashFraction, 1 wei, 1 ether);

        // Setup
        {
            // Perform the deposit as Alice
            deal(address(weth), alice, depositAmount);
            vm.startPrank(alice);
            weth.approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        {
            // Deposit from Bob
            // Mint WETH to Bob
            deal(address(weth), bob, bufferDepositAmount);

            // Approve vault to spend Bob's WETH
            vm.startPrank(bob);
            weth.approve(address(vault), bufferDepositAmount);

            // Bob deposits WETH into the vault
            vault.deposit(bufferDepositAmount, bob);
            vm.stopPrank();

            // Allocate the deposited WETH to the mock buffer strategy
            ProcessorUtils.allocateToERC4626(
                address(vault), address(weth), address(MC.BUFFER), bufferDepositAmount, PROCESSOR
            );
        }

        // Allocate the deposited WETH to the mock vault strategy
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(mockVault), depositAmount, PROCESSOR);

        // Verify the allocation was successful
        assertEq(weth.balanceOf(address(vault)), 0, "Vault should have transferred all WETH");
        assertEq(
            IERC20(address(mockVault)).balanceOf(address(vault)),
            depositAmount,
            "Mock vault should have received the deposit amount"
        );

        // Store the total assets before slashing
        uint256 totalAssetsBeforeSlash = vault.totalAssets();
        uint256 aliceShares = vault.balanceOf(alice);

        // Use the slash function to simulate the loss
        mockVault.slash(slashFraction);

        // Call processAccounting to update the vault's accounting
        vm.prank(PROCESSOR);
        vault.processAccounting();

        // Verify that total assets have been updated after processAccounting
        uint256 totalAssetsAfterAccounting = vault.totalAssets();
        assertLt(
            totalAssetsAfterAccounting,
            totalAssetsBeforeSlash,
            "Total assets should decrease after processAccounting due to slashing"
        );

        // Calculate expected assets after slashing
        uint256 expectedAssetsAfterSlash = totalAssetsBeforeSlash - (depositAmount * slashFraction / 1 ether);
        assertApproxEqAbs(
            totalAssetsAfterAccounting,
            expectedAssetsAfterSlash,
            2, // Increased tolerance for fuzzing
            "Total assets should reflect approximately slashFraction/1e18 of mock vault being slashed"
        );

        // Test withdrawal for Alice
        uint256 expectedWithdrawAmount = vault.previewRedeem(aliceShares);

        vm.startPrank(alice);
        uint256 withdrawnAmount = vault.redeem(aliceShares, alice, alice);
        vm.stopPrank();

        // Verify withdrawal amount reflects the slashing
        assertEq(withdrawnAmount, expectedWithdrawAmount, "Withdrawn amount should match preview");

        // Only assert this if the slashing is significant enough
        if (slashFraction > 0.05 ether) {
            assertLt(withdrawnAmount, depositAmount, "Withdrawn amount should be less than deposit due to slashing");
        }

        // Since slashing only affects the portion of assets in the mock vault,
        // the withdrawn amount should reflect the partial impact on the total assets
        uint256 expectedWithdrawnAmount = depositAmount * (totalAssetsAfterAccounting) / totalAssetsBeforeSlash;
        assertApproxEqAbs(
            withdrawnAmount,
            expectedWithdrawnAmount,
            2, // Increased tolerance for fuzzing
            "Withdrawn amount should reflect the partial slashing of vault assets"
        );
    }

    function test_Withdrawal_Before_Processing_Slashing_Loss(
        uint256 depositAmount,
        uint256 slashFraction,
        uint256 bufferDepositAmount
    ) public {
        // Bound inputs to reasonable values
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        slashFraction = bound(slashFraction, 1 wei, 1 ether);
        bufferDepositAmount = bound(bufferDepositAmount, depositAmount, 100_000 ether); // Buffer between 10% and 200% of deposit

        // Alice deposits
        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);
        uint256 aliceShares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Allocate the deposited WETH to the mock vault strategy
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(mockVault), depositAmount, PROCESSOR);

        {
            // Deposit from Bob
            // Mint WETH to Bob
            deal(address(weth), bob, bufferDepositAmount);

            // Approve vault to spend Bob's WETH
            vm.startPrank(bob);
            weth.approve(address(vault), bufferDepositAmount);

            // Bob deposits WETH into the vault
            vault.deposit(bufferDepositAmount, bob);
            vm.stopPrank();

            // Allocate the deposited WETH to the mock buffer strategy
            ProcessorUtils.allocateToERC4626(
                address(vault), address(weth), address(MC.BUFFER), bufferDepositAmount, PROCESSOR
            );
        }

        // Record total assets before slashing
        uint256 totalAssetsBeforeSlash = vault.totalAssets();

        // Use the slash function to simulate the loss
        mockVault.slash(slashFraction);

        // Verify that total assets have NOT been updated without processAccounting
        uint256 totalAssetsAfterSlash = vault.totalAssets();
        assertEq(
            totalAssetsAfterSlash,
            totalAssetsBeforeSlash,
            "Total assets should only reflect buffer allocation without processAccounting"
        );

        vm.startPrank(alice);
        uint256 withdrawnAmount = vault.redeem(aliceShares, alice, alice);
        vm.stopPrank();

        // Verify withdrawal amount does not reflect the slashing
        assertEq(withdrawnAmount, depositAmount, "Withdrawn amount should match deposit amount");

        // The withdrawn amount should be close to the original deposit since processAccounting wasn't called
        // But it might be slightly higher due to the buffer allocation
        uint256 expectedWithdrawnWithBuffer = depositAmount;
        assertApproxEqAbs(
            withdrawnAmount,
            expectedWithdrawnWithBuffer,
            1, // Increased tolerance for fuzzing
            "Withdrawn amount should reflect buffer allocation but not slashing"
        );

        vault.processAccounting();

        {
            // Verify that total assets have been updated after processAccounting
            uint256 totalAssetsAfterProcessing = vault.totalAssets();

            // Calculate expected assets after slashing and withdrawal
            // Calculate expected assets after slashing based on the proportion of assets in the vault
            uint256 expectedAssetsAfterSlashing = totalAssetsBeforeSlash - (depositAmount * slashFraction / 1e18);
            // Calculate the loss based on the ratio of depositAmount and slashFraction
            uint256 expectedAssetsAfterWithdrawal = expectedAssetsAfterSlashing - withdrawnAmount;

            assertApproxEqAbs(
                totalAssetsAfterProcessing,
                expectedAssetsAfterWithdrawal,
                1, // Small tolerance for rounding
                "Total assets should reflect both slashing and withdrawal after processing"
            );
        }
    }
}
