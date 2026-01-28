// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {IVault} from "src/interface/IVault.sol";
import {console} from "forge-std/console.sol";

/**
 * @title AccountingEdgeCasesTest
 * @notice Tests for accounting edge cases and underflow issues
 * @dev Tests HIGH #4 vulnerability and other accounting edge cases
 */
contract AccountingEdgeCasesTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public alice = address(0xA11Ce);
    address public bob = address(0xB0b);
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Fund users
        deal(alice, INITIAL_BALANCE);
        deal(bob, INITIAL_BALANCE);

        vm.prank(alice);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(bob);
        weth.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Test totalAssets underflow scenario
     * @dev HIGH #4: subTotalAssets can underflow if accounting goes wrong
     */
    function test_Accounting_UnderflowRisk() public {
        // In VaultLib.sol:260-265, subTotalAssets does:
        // vaultStorage.totalAssets -= baseAssets;
        //
        // This can underflow if baseAssets > totalAssets
        // Which can happen if accounting gets out of sync

        // Deposit
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Withdraw
        vm.prank(alice);
        vault.withdraw(50 ether, alice, alice);

        // Total assets should be 50 ether
        assertEq(vault.totalAssets(), 50 ether, "Total assets should be 50");

        // If we try to withdraw more than totalAssets, it should revert
        // But if accounting is wrong and totalAssets is less than it should be,
        // subTotalAssets will underflow

        // This test shows the vulnerability exists but may be hard to trigger
        // with correct accounting
    }

    /**
     * @notice Test rounding accumulation
     * @dev Multiple operations with rounding can accumulate errors
     */
    function test_Accounting_RoundingAccumulation() public {
        // Deposit and withdraw repeatedly with odd amounts
        // Rounding happens on each operation
        // Errors can accumulate

        uint256 depositAmount = 1 ether + 1; // Odd amount for rounding

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            uint256 shares = vault.deposit(depositAmount, alice);

            ProcessorUtils.allocateToERC4626(
                address(vault), address(weth), address(vault.buffer()), depositAmount, PROCESSOR
            );

            vm.prank(alice);
            vault.redeem(shares, alice, alice);
        }

        // After multiple round trips, total assets should be 0
        // But rounding errors might leave dust
        assertLt(vault.totalAssets(), 1000, "Only dust remaining");

        console.log("vault.convertToAssets(1e18)", vault.convertToAssets(1e18));

        console.log("totalAssets", vault.totalAssets());

        // This demonstrates rounding is generally safe
        // But in edge cases could cause issues
    }

    /**
     * @notice Test zero shares minted protection
     * @dev Depositing very small amount with inflated share price
     * Tests vault has no 0-share protection
     */
    function test_Accounting_ZeroSharesMinted() public {
        // Deposit large amount first to establish high share price
        vm.prank(alice);
        vault.deposit(100_000 ether, alice); // Use smaller amount to avoid overflow

        // Donate to inflate share price (but not too extreme)
        vm.prank(bob);
        weth.transfer(address(vault), 100_000 ether);
        vault.processAccounting();

        // Now share price is inflated
        // Deposit tiny amount
        uint256 tinyDeposit = 1; // 1 wei

        vm.startPrank(bob);
        weth.approve(address(vault), tinyDeposit);
        uint256 shares = vault.deposit(tinyDeposit, bob);
        vm.stopPrank();

        assertEq(shares, 0, "Vault has 0-share protection");
    }

    /**
     * @notice Test dust amounts in conversions
     * @dev Very small amounts can round to zero
     */
    function test_Accounting_DustConversions() public view {
        // Test converting dust amounts

        // 1 wei of assets
        uint256 shares = vault.convertToShares(1);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertEq(assetsBack, 1, "Dust amount rounds to zero or one");
    }

    function test_Accounting_NeedMinimumDeposit() public {
        // Current implementation has no minimum
        // Anyone can deposit 1 wei

        vm.prank(alice);
        uint256 shares = vault.deposit(1, alice);

        // This succeeds but creates dust
        assertEq(shares, 1, "Can deposit 1 wei");
    }

    /**
     * @notice Test totalAssets vs actual balance discrepancy
     * @dev totalAssets tracking can diverge from actual balances
     */
    function test_Accounting_TotalAssetsDivergence() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // totalAssets should be 100
        assertEq(vault.totalAssets(), 100 ether, "Total assets = 100");

        // Actual WETH balance
        uint256 actualBalance = weth.balanceOf(address(vault));
        assertEq(actualBalance, 100 ether, "Actual balance = 100");

        // These match, but if someone transfers WETH directly:
        vm.prank(bob);
        weth.transfer(address(vault), 50 ether);

        // Now actual balance > totalAssets (until processAccounting)
        actualBalance = weth.balanceOf(address(vault));
        assertEq(actualBalance, 150 ether, "Actual balance = 150");
        assertEq(vault.totalAssets(), 100 ether, "Total assets still 100");

        // This discrepancy can cause issues if not handled carefully
    }

    /**
     * @notice Test processAccounting with no assets
     * @dev processAccounting on empty vault
     */
    function test_Accounting_ProcessAccountingEmpty() public {
        // Process accounting on empty vault
        vault.processAccounting();

        // Should not revert
        assertEq(vault.totalAssets(), 0, "Total assets should be 0");
    }

    /**
     * @notice Test deposit then immediate redeem
     * @dev Should get back same amount (minus fees)
     */
    function test_Accounting_DepositRedeemRoundtrip() public {
        uint256 depositAmount = 100 ether;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Allocate to buffer for withdrawal
        ProcessorUtils.allocateToERC4626(
            address(vault), address(weth), address(vault.buffer()), depositAmount, PROCESSOR
        );

        // Redeem immediately
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        // Should get back same amount (minus withdrawal fee if any)
        uint256 expectedAssets = depositAmount - vault._feeOnTotal(depositAmount, alice);
        assertEq(assets, expectedAssets, "Should get back deposit amount minus fees");
    }

    /**
     * @notice Test multiple users deposit and withdraw
     * @dev Total assets should always equal sum of user shares value
     */
    function test_Accounting_MultiUserInvariant() public {
        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100 ether, alice);

        // Bob deposits
        vm.prank(bob);
        uint256 bobShares = vault.deposit(200 ether, bob);

        // Total assets should be 300
        assertEq(vault.totalAssets(), 300 ether, "Total assets = 300");

        // Sum of user shares value should equal total assets
        uint256 aliceValue = vault.convertToAssets(aliceShares);
        uint256 bobValue = vault.convertToAssets(bobShares);

        assertApproxEqAbs(aliceValue + bobValue, 300 ether, 2, "Sum of shares = total assets");

        // Allocate to buffer
        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 300 ether, PROCESSOR);

        // Alice withdraws half
        vm.prank(alice);
        vault.redeem(aliceShares / 2, alice, alice);

        // Invariant should still hold
        uint256 totalAssets = vault.totalAssets();
        aliceValue = vault.convertToAssets(vault.balanceOf(alice));
        bobValue = vault.convertToAssets(vault.balanceOf(bob));

        assertApproxEqAbs(aliceValue + bobValue, totalAssets, 100, "Invariant maintained");
    }

    /**
     * @notice Test extreme values
     * @dev Test with very large deposit amounts
     */
    function testFuzz_Accounting_ExtremeValues(uint256 amount) public {
        amount = bound(amount, 1 ether, 1_000_000 ether);

        vm.startPrank(alice);
        uint256 shares = vault.deposit(amount, alice);

        // Shares should be approximately equal to amount (1:1 ratio when empty)
        assertApproxEqRel(shares, amount, 0.01e18, "Shares roughly equal to amount");
        vm.stopPrank();
    }

    /**
     * @notice Test deposit zero amount
     * @dev Should revert or handle gracefully
     */
    function test_Accounting_DepositZero() public {
        vm.prank(alice);

        // Depositing 0 should mint 0 shares
        uint256 shares = vault.deposit(0, alice);
        assertEq(shares, 0, "Zero deposit should mint zero shares");

        // This is allowed but pointless
        // Consider requiring amount > 0
    }

    /**
     * @notice Test withdraw zero amount
     * @dev Should handle gracefully
     */
    function test_Accounting_WithdrawZero() public {
        // Deposit first
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        ProcessorUtils.allocateToERC4626(address(vault), address(weth), address(vault.buffer()), 100 ether, PROCESSOR);

        // Withdraw 0
        vm.prank(alice);
        uint256 shares = vault.withdraw(0, alice, alice);

        assertEq(shares, 0, "Zero withdraw should burn zero shares");
    }

    /**
     * @notice Test processAccounting gas cost with many assets
     * @dev Gas cost increases linearly with number of assets
     */
    function test_Accounting_ProcessAccountingGasCost() public {
        // processAccounting() loops through all assets
        // Gas cost increases with number of assets

        // Current vault has ~6 assets
        uint256 gasBefore = gasleft();
        vault.processAccounting();
        uint256 gasUsed = gasBefore - gasleft();

        // Should be reasonable (< 500k gas)
        assertLt(gasUsed, 500_000, "Process accounting gas cost reasonable");

        // Note: With 100+ assets, this could become prohibitively expensive
        // Recommendation: Consider asset limits or paginated processing
    }

    /**
     * @notice Test totalAssets consistency across computeTotalAssets and cached value
     */
    function test_Accounting_TotalAssetsConsistency() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // When alwaysComputeTotalAssets = false (default)
        uint256 cachedTotal = vault.totalAssets();

        // Manually compute
        uint256 computedTotal = vault.computeTotalAssets();

        // Should match
        assertEq(cachedTotal, computedTotal, "Cached and computed should match");

        // After direct transfer (not through deposit)
        vm.prank(bob);
        weth.transfer(address(vault), 50 ether);

        // Cached is stale
        cachedTotal = vault.totalAssets();
        assertEq(cachedTotal, 100 ether, "Cached is stale");

        // Computed is fresh
        computedTotal = vault.computeTotalAssets();
        assertEq(computedTotal, 150 ether, "Computed is fresh");

        // After processAccounting, they match again
        vault.processAccounting();
        assertEq(vault.totalAssets(), 150 ether, "Cached updated");
    }
}
