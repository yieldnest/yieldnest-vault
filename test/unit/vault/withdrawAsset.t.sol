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
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {Math} from "src/Common.sol";

contract VaultWithdrawAssetUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);
    address public withdrawerManager = address(0x4);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        // Grant ASSET_WITHDRAWER_ROLE to withdrawerManager
        vm.startPrank(ADMIN);
        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), withdrawerManager);
        vm.stopPrank();
    }

    function test_withdrawAsset_DefaultAsset(uint256 depositAmount, uint256 withdrawAmount, bool callProcessAccounting)
        public
    {
        // Bound deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1000, 100_000 ether); // At least 1000 wei to avoid rounding issues, up to 100k ETH

        // Ensure withdraw amount is between 1 and deposit amount
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Give Bob some tokens and have him deposit
        deal(bob, INITIAL_BALANCE);
        vm.startPrank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.approve(address(vault), type(uint256).max);
        uint256 sharesReceived = vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Bob sends his shares to withdrawerManager
        vm.startPrank(bob);
        vault.transfer(withdrawerManager, vault.balanceOf(bob));
        vm.stopPrank();

        // Record state before withdrawal
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        // Calculate expected shares to burn
        uint256 expectedSharesToBurn = vault.previewWithdraw(withdrawAmount);

        // Withdraw WETH using withdrawAsset (withdrawerManager withdraws for withdrawerManager)
        vm.prank(withdrawerManager);
        uint256 sharesBurned = vault.withdrawAsset(address(weth), withdrawAmount, withdrawerManager, withdrawerManager);

        if (callProcessAccounting) {
            vault.processAccounting();
        }

        // Verify the correct amount of shares were burned
        assertEq(sharesBurned, expectedSharesToBurn, "Shares burned should match preview");

        // Verify withdrawerManager's share balance decreased
        assertEq(
            vault.balanceOf(withdrawerManager),
            sharesReceived - sharesBurned,
            "WithdrawerManager's shares should be reduced by burned amount"
        );

        // Verify total supply decreased
        assertEq(
            vault.totalSupply(), totalSupplyBefore - sharesBurned, "Total supply should be reduced by burned amount"
        );

        // Verify total assets decreased
        assertEq(
            vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets should be reduced by withdraw amount"
        );

        // Verify withdrawerManager received the withdrawn WETH
        assertEq(
            weth.balanceOf(withdrawerManager),
            withdrawAmount,
            "WithdrawerManager should have received the withdrawn WETH"
        );
    }

    function test_withdrawAsset_AnyAsset(
        uint256 depositAmount,
        uint256 withdrawAmount,
        bool callProcessAccounting,
        uint8 assetIndexUint8
    ) public {
        // Create array of assets including WETH and the 3 additional assets
        address[] memory assets = new address[](4);
        assets[0] = MC.WETH;
        assets[1] = MC.STETH;
        assets[2] = MC.WBTC;
        assets[3] = MC.METH;

        // Select one asset for testing (using modulo to ensure valid index)
        uint256 assetIndex = assetIndexUint8 % assets.length;
        address selectedAsset = assets[assetIndex];

        depositAmount = bound(depositAmount, 1001, 100_000 * (10 ** IERC20Metadata(selectedAsset).decimals()) - 1);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Deal the selected asset to bob
        deal(selectedAsset, bob, depositAmount);

        // Bob deposits the selected asset
        vm.startPrank(bob);
        IERC20(selectedAsset).approve(address(vault), depositAmount);
        uint256 sharesReceived = vault.depositAsset(selectedAsset, depositAmount, bob);
        vm.stopPrank();

        // Bob sends his shares to withdrawerManager
        vm.startPrank(bob);
        vault.transfer(withdrawerManager, vault.balanceOf(bob));
        vm.stopPrank();

        // Record state before withdrawal
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        // Calculate expected shares to burn
        (uint256 expectedSharesToBurn,) = PublicViewsVault(payable(address(vault))).convertToSharesForAsset(
            selectedAsset, withdrawAmount, Math.Rounding.Ceil
        ); // vault.previewWithdraw(withdrawAmount);

        // Withdraw selected asset using withdrawAsset (withdrawerManager withdraws for withdrawerManager)
        vm.prank(withdrawerManager);
        uint256 sharesBurned = vault.withdrawAsset(selectedAsset, withdrawAmount, withdrawerManager, withdrawerManager);

        if (callProcessAccounting) {
            vault.processAccounting();
        }

        // Verify the correct amount of shares were burned
        assertEq(sharesBurned, expectedSharesToBurn, "Shares burned should match preview");

        // Verify withdrawerManager's share balance decreased
        assertEq(
            vault.balanceOf(withdrawerManager),
            sharesReceived - sharesBurned,
            "WithdrawerManager's shares should be reduced by burned amount"
        );

        // Verify total supply decreased
        assertEq(
            vault.totalSupply(), totalSupplyBefore - sharesBurned, "Total supply should be reduced by burned amount"
        );

        // Verify total assets decreased
        uint256 withdrawAmountInBase =
            PublicViewsVault(payable(address(vault))).convertAssetToBase(selectedAsset, withdrawAmount);
        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore - withdrawAmountInBase,
            1,
            "Total assets should be reduced by withdraw amount"
        );

        // Verify withdrawerManager received the withdrawn asset
        assertEq(
            IERC20(selectedAsset).balanceOf(withdrawerManager),
            withdrawAmount,
            "WithdrawerManager should have received the withdrawn asset"
        );
    }

    function test_withdrawAsset_InsufficientShares() public {
        uint256 depositAmount = 1000 ether;
        uint256 withdrawAmount = 500 ether;

        // Give Bob some tokens and have him deposit
        deal(bob, INITIAL_BALANCE);
        vm.startPrank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.approve(address(vault), type(uint256).max);
        uint256 sharesReceived = vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Transfer vault tokens to the vault to ensure it has enough assets
        vm.prank(bob);
        weth.transfer(address(vault), withdrawAmount);

        // Calculate required shares for withdrawal
        (uint256 requiredShares,) = PublicViewsVault(payable(address(vault))).convertToSharesForAsset(
            address(weth), withdrawAmount, Math.Rounding.Ceil
        );

        // Burn most of Bob's shares, leaving insufficient shares for withdrawal
        vm.prank(bob);
        vault.transfer(alice, sharesReceived * 2 / 3);

        // Verify Bob has insufficient shares
        assertLt(vault.balanceOf(bob), requiredShares, "Bob should have insufficient shares");

        // Attempt to withdraw should revert with ExceededMaxWithdraw
        vm.startPrank(withdrawerManager);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ExceededMaxWithdraw(address,uint256,uint256)",
                bob,
                withdrawAmount,
                IERC20(address(weth)).balanceOf(address(vault))
            )
        );
        vault.withdrawAsset(address(weth), withdrawAmount, withdrawerManager, bob);
        vm.stopPrank();
    }

    function test_withdrawAsset_InsufficientAssets() public {
        uint256 depositAmount = 1000 ether;
        uint256 withdrawAmount = 500 ether;

        // Give Bob some tokens and have him deposit
        deal(bob, INITIAL_BALANCE);
        vm.startPrank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Ensure vault has insufficient assets by not transferring any additional tokens
        // The vault should only have the buffer amount from deposit

        uint256 vaultAssetBalance = IERC20(address(weth)).balanceOf(address(vault));

        // Try to withdraw more than the vault has
        uint256 excessiveWithdrawAmount = vaultAssetBalance + 1;

        // Attempt to withdraw should revert with ExceededMaxWithdraw
        vm.startPrank(withdrawerManager);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ExceededMaxWithdraw(address,uint256,uint256)", bob, excessiveWithdrawAmount, vaultAssetBalance
            )
        );
        vault.withdrawAsset(address(weth), excessiveWithdrawAmount, withdrawerManager, bob);
        vm.stopPrank();
    }

    function test_withdrawAsset_WithAllowanceButNoTransfer(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1000, 10000 ether);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Give Bob some tokens and have him deposit
        deal(bob, INITIAL_BALANCE);
        vm.startPrank(bob);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.approve(address(vault), type(uint256).max);
        uint256 sharesReceived = vault.deposit(depositAmount, bob);

        // Bob gives allowance to withdrawerManager for the exact amount needed
        vault.approve(withdrawerManager, sharesReceived);
        vm.stopPrank();

        // Verify Bob still owns the shares
        assertEq(vault.balanceOf(bob), sharesReceived, "Bob should still own all shares");
        assertEq(vault.balanceOf(withdrawerManager), 0, "WithdrawerManager should have no shares");

        // Verify allowance is set
        assertEq(vault.allowance(bob, withdrawerManager), sharesReceived, "Allowance should be set");

        uint256 initialBobBalance = weth.balanceOf(bob);
        uint256 initialManagerBalance = weth.balanceOf(withdrawerManager);
        uint256 initialVaultBalance = weth.balanceOf(address(vault));

        // WithdrawerManager should be able to withdraw on behalf of Bob
        vm.startPrank(withdrawerManager);
        uint256 sharesWithdrawn = vault.withdrawAsset(address(weth), withdrawAmount, withdrawerManager, bob);
        vm.stopPrank();

        // Verify the withdrawal was successful
        assertEq(
            weth.balanceOf(withdrawerManager),
            initialManagerBalance + withdrawAmount,
            "Manager should receive the assets"
        );
        assertEq(weth.balanceOf(bob), initialBobBalance, "Bob's balance should remain unchanged");
        assertEq(weth.balanceOf(address(vault)), initialVaultBalance - withdrawAmount, "Vault balance should decrease");
        assertEq(vault.balanceOf(bob), sharesReceived - sharesWithdrawn, "Bob's shares should be burned");
        assertEq(vault.allowance(bob, withdrawerManager), sharesReceived - sharesWithdrawn, "Allowance should be 0");

        // Verify the asset was withdrawn to the correct receiver (withdrawerManager)
        assertEq(
            weth.balanceOf(withdrawerManager),
            initialManagerBalance + withdrawAmount,
            "WithdrawerManager should receive the withdrawn assets"
        );
    }
}
