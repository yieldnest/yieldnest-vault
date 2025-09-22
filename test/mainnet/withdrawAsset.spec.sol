// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract ProcessorIntegrationTest is BaseIntegrationTest {
    address public withdrawerOperator;

    function setUp() public override {
        super.setUp();

        withdrawerOperator = makeAddr("withdrawerOperator");

        vm.startPrank(ADMIN);
        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), withdrawerOperator);
        vm.stopPrank();
    }

    function test_depositAsset_WETH_withdrawAsset_WETH() public {
        address alice = makeAddr("alice");
        uint256 depositAmount = 1e18;
        deal(MC.WETH, alice, depositAmount);

        uint256 allowance = 100_000 ether;

        vm.startPrank(alice);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, alice);

        IERC20(address(vault)).approve(withdrawerOperator, allowance);
        vm.stopPrank();

        // Store initial state for assertions
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialRate = vault.convertToAssets(1e18); // Rate per share (1 share = X assets)

        // can withdraw 1 wei less, in favor of rounding for the vault
        uint256 withdrawAmount = depositAmount - 1;

        vm.startPrank(withdrawerOperator);
        uint256 sharesBurned = vault.withdrawAsset(MC.WETH, withdrawAmount, alice, alice);
        vm.stopPrank();

        assertEq(IERC20(MC.WETH).balanceOf(alice), withdrawAmount, "Alice should have withdrawn WETH");

        assertEq(IERC20(MC.WETH).balanceOf(withdrawerOperator), 0, "Withdrawer operator should have no WETH");

        // Assert that the allowance was properly used
        uint256 remainingAllowance = IERC20(address(vault)).allowance(alice, withdrawerOperator);
        assertEq(remainingAllowance, allowance - sharesBurned, "Allowance should be reduced by sharesBurned");

        // Assert rate does not change
        uint256 finalRate = vault.convertToAssets(1e18);
        assertEq(finalRate, initialRate, "Rate should remain unchanged");

        // Assert totalSupply stays the same (shares burned but not from total supply)
        uint256 finalTotalSupply = vault.totalSupply();
        assertEq(finalTotalSupply, initialTotalSupply - sharesBurned, "Total supply should be reduced by shares burned");

        // Assert totalAssets is as expected (reduced by withdrawn amount converted to base)
        uint256 finalTotalAssets = vault.totalAssets();
        uint256 expectedTotalAssets = initialTotalAssets - withdrawAmount; // Assuming WETH is 1:1 with base asset
        assertEq(finalTotalAssets, expectedTotalAssets, "Total assets should be reduced by withdrawn amount");
    }
}
