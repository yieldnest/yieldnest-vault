// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

contract VaultInvariantsTest is Test, MainnetActors, Etches {
    PublicViewsVault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        Vault _vault;
        (_vault, weth) = setupVault.setup();

        vault = PublicViewsVault(payable(address(_vault)));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_convertAssetToBase_Consistency(uint256 assets) public view {
        vm.assume(assets > 0);
        vm.assume(assets < type(uint256).max / 1e18); // Prevent overflow

        // First conversion
        uint256 convertedAssets = vault.convertAssetToBase(vault.asset(), assets);
        // Assert that both conversions yield the same result
        assertEq(convertedAssets, assets, "Asset to base conversion should be consistent");
    }

    function test_Vault_totalAssets_Equals_totalSupply_When_Empty() public view {
        // When the vault is empty, totalAssets should equal 0 and totalSupply should equal 0
        assertEq(vault.totalAssets(), 0, "Total assets should be 0 when vault is empty");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0 when vault is empty");
    }

    function test_Vault_deposit_withdraw_Invariant(uint256 amount) public {
        vm.assume(amount > 0 && amount < INITIAL_BALANCE / 2);

        // Initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialAliceBalance = weth.balanceOf(alice);

        // Deposit
        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        // Check invariants after deposit
        assertEq(vault.totalAssets(), initialTotalAssets + amount, "Total assets should increase by deposit amount");
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares minted");
        assertEq(
            weth.balanceOf(alice), initialAliceBalance - amount, "Alice's balance should decrease by deposit amount"
        );

        ProcessorUtils.allocateToERC4626(
            address(vault), address(weth), address(vault.buffer()), vault.totalAssets(), PROCESSOR
        );

        // Withdraw
        vm.prank(alice);
        uint256 assetsWithdrawn = vault.redeem(shares, alice, alice);

        // Check invariants after withdrawal
        assertEq(vault.totalAssets(), initialTotalAssets, "Total assets should return to initial state");
        assertEq(vault.totalSupply(), initialTotalSupply, "Total supply should return to initial state");
        assertEq(
            weth.balanceOf(alice), initialAliceBalance - amount + assetsWithdrawn, "Alice's balance should be restored"
        );
    }

    function test_Vault_convertToShares_convertToAssets_Roundtrip(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        // First deposit to initialize the vault
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        // Convert assets to shares
        uint256 shares = vault.convertToShares(amount);

        // Convert shares back to assets
        uint256 assets = vault.convertToAssets(shares);

        // Due to rounding, we may lose some precision, but the difference should be minimal
        uint256 tolerance = 1; // Allow for 1 wei of rounding error
        assertApproxEqAbs(assets, amount, tolerance, "Asset to share to asset conversion should be consistent");
    }

    function test_Vault_maxDeposit_maxMint_Consistency() public {
        // When not paused, maxDeposit should be max uint256
        uint256 maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max, "Max deposit should be max uint256 when not paused");

        // When paused, maxDeposit should be 0
        vm.prank(PAUSER);
        vault.pause();
        maxDeposit = vault.maxDeposit(alice);
        assertEq(maxDeposit, 0, "Max deposit should be 0 when paused");

        // Unpause for further tests
        vm.prank(UNPAUSER);
        vault.unpause();
    }

    function test_Vault_previewDeposit_deposit_Consistency(uint256 amount) public {
        vm.assume(amount > 0 && amount < INITIAL_BALANCE / 2);

        // Preview deposit
        uint256 expectedShares = vault.previewDeposit(amount);

        // Actual deposit
        vm.prank(alice);
        uint256 actualShares = vault.deposit(amount, alice);

        // The actual shares should be greater than or equal to the preview
        assertEq(actualShares, expectedShares, "Actual shares should be >= previewed shares");
    }

    function test_Vault_previewMint_mint_Consistency(uint256 shares) public {
        vm.assume(shares > 0 && shares < type(uint128).max / 1e18);

        // Preview mint
        uint256 expectedAssets = vault.previewMint(shares);

        // Actual mint
        vm.prank(alice);
        uint256 actualAssets = vault.mint(shares, alice);

        // The actual assets should be equal to the preview
        assertEq(actualAssets, expectedAssets, "Actual assets should be equal to previewed assets");
    }

    function test_Vault_previewWithdraw_withdraw_Consistency(uint256 amount) public {
        vm.assume(amount > 0 && amount < INITIAL_BALANCE / 2);

        // First deposit to have some shares
        vm.prank(alice);
        vault.deposit(amount * 2, alice);

        // Preview withdraw
        uint256 expectedShares = vault.previewWithdraw(amount);

        ProcessorUtils.allocateToERC4626(
            address(vault), address(weth), address(vault.buffer()), vault.totalAssets(), PROCESSOR
        );

        // Actual withdraw
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(amount, alice, alice);

        // The actual shares should be less than or equal to the preview
        assertEq(actualShares, expectedShares, "Actual shares should match previewed shares");
    }

    function test_Vault_previewRedeem_redeem_Consistency(uint256 shares) public {
        vm.assume(shares > 0 && shares < INITIAL_BALANCE / 2);

        // First deposit to have some shares
        vm.prank(alice);
        vault.deposit(shares * 2, alice);

        // Preview redeem
        uint256 expectedAssets = vault.previewRedeem(shares);

        ProcessorUtils.allocateToERC4626(
            address(vault), address(weth), address(vault.buffer()), vault.totalAssets(), PROCESSOR
        );

        // Actual redeem
        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        // The actual assets should be equal to the preview
        assertEq(actualAssets, expectedAssets, "Actual assets should match previewed assets");
    }

    function test_Vault_maxWithdraw_maxRedeem_Consistency(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < INITIAL_BALANCE / 2);

        // First deposit to have some shares
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Check maxWithdraw and maxRedeem consistency
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        uint256 maxRedeem = vault.maxRedeem(alice);
        uint256 convertedMaxRedeem = vault.convertToAssets(maxRedeem);

        // Due to rounding, we may lose some precision, but the difference should be minimal
        uint256 tolerance = 1; // Allow for 1 wei of rounding error
        assertApproxEqAbs(maxWithdraw, convertedMaxRedeem, tolerance, "maxWithdraw should be consistent with maxRedeem");

        // When paused, both should be 0
        vm.prank(PAUSER);
        vault.pause();

        maxWithdraw = vault.maxWithdraw(alice);
        maxRedeem = vault.maxRedeem(alice);

        assertEq(maxWithdraw, 0, "Max withdraw should be 0 when paused");
        assertEq(maxRedeem, 0, "Max redeem should be 0 when paused");

        // Unpause for further tests
        vm.prank(UNPAUSER);
        vault.unpause();
    }

    function test_Vault_depositAsset_Consistency(uint256 amount) public {
        vm.assume(amount > 0 && amount < INITIAL_BALANCE / 2);

        // Give alice some STETH
        deal(address(MC.STETH), alice, amount);

        vm.startPrank(alice);
        IERC20(MC.STETH).approve(address(vault), amount);

        // Preview deposit asset
        uint256 expectedShares = vault.previewDepositAsset(MC.STETH, amount);

        // Actual deposit asset
        uint256 actualShares = vault.depositAsset(MC.STETH, amount, alice);

        // The actual shares should be equal to the preview
        assertEq(actualShares, expectedShares, "Actual shares should match previewed shares");
        vm.stopPrank();
    }

    function test_Vault_convertToAssets_convertToShares_Roundtrip(uint256 amount) public view {
        vm.assume(amount > 0 && amount < type(uint128).max);

        // Convert assets to shares
        uint256 shares = vault.convertToShares(amount);

        // Convert shares back to assets
        uint256 assets = vault.convertToAssets(shares);

        // Due to rounding, we may lose some precision, but the difference should be minimal
        uint256 tolerance = 1; // Allow for 1 wei of rounding error
        assertApproxEqAbs(assets, amount, tolerance, "Asset to share to asset conversion should be consistent");
    }

    function test_Vault_totalSupply_totalAssets_Consistency(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < INITIAL_BALANCE / 2);

        // Deposit some assets
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Total supply of shares should match total assets when exchange rate is 1:1
        assertEq(vault.totalSupply(), vault.totalAssets(), "Total supply should match total assets");

        // This invariant holds only when the exchange rate is 1:1
        // In a real-world scenario with yield, this would need to be adjusted
    }
}
