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
import {HooksUtils} from "test/utils/HooksUtils.sol";

contract VaultMintUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
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
    }

    function test_Vault_mint(uint256 mintAmount, bool alwaysComputeTotalAssets) public {
        if (mintAmount < 10) return;
        if (mintAmount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.startPrank(alice);
        uint256 sharesMinted = vault.mint(mintAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets did not change
        assertEq(vault.totalAssets(), mintAmount, "Total assets changed incorrectly");

        assertEq(vault.convertToShares(1e18), 1e18, "Conversion to shares did not reflect mint");

        vm.stopPrank();
    }

    function test_Vault_mint_1_wei(bool alwaysComputeTotalAssets) public {
        uint256 mintAmount = 1 wei;
        uint256 assetsRequired = 1 wei;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Make sure Alice has enough WETH to mint 1 share
        assertGe(weth.balanceOf(alice), assetsRequired, "Alice does not have enough WETH to mint 1 wei shares");

        vm.startPrank(alice);
        weth.approve(address(vault), assetsRequired);
        uint256 sharesMinted = vault.mint(mintAmount, alice);
        vm.stopPrank();

        assertEq(sharesMinted, mintAmount, "Incorrect shares minted for 1 wei mint");

        // Vault should receive exactly 1 wei
        assertEq(weth.balanceOf(address(vault)), assetsRequired, "Vault did not receive 1 wei for 1 wei mint");

        // Alice's WETH should decrease by 1 wei
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - assetsRequired, "Alice's WETH did not decrease by 1 wei");

        // Alice's Vault token balance should be 1 wei
        assertEq(vault.balanceOf(alice), mintAmount, "Alice did not receive 1 wei shares");

        // Vault totalAssets should increase by 1 wei
        assertEq(vault.totalAssets(), assetsRequired, "Vault total assets did not reflect 1 wei mint");

        // Conversion should stay consistent
        assertEq(vault.convertToShares(assetsRequired), mintAmount, "Conversion to shares did not reflect 1 wei mint");

        assertEq(vault.convertToShares(1e18), 1e18, "Conversion to shares did not reflect mint");

        if (!alwaysComputeTotalAssets) {
            vault.processAccounting();

            // states stays the same
            assertEq(vault.totalAssets(), assetsRequired, "Vault total assets did not reflect 1 wei mint");
            assertEq(vault.balanceOf(alice), mintAmount, "Alice did not receive 1 wei shares");
            assertEq(weth.balanceOf(address(vault)), assetsRequired, "Vault did not receive 1 wei for 1 wei mint");
            assertEq(weth.balanceOf(alice), INITIAL_BALANCE - assetsRequired, "Alice's WETH did not decrease by 1 wei");
            assertEq(
                vault.convertToShares(assetsRequired), mintAmount, "Conversion to shares did not reflect 1 wei mint"
            );

            assertEq(vault.convertToShares(1e18), 1e18, "Conversion to shares did not reflect mint");
        }
    }

    function test_Vault_mint_zero_shares(bool alwaysComputeTotalAssets) public {
        uint256 mintAmount = 0;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 initialWethBalance = weth.balanceOf(alice);

        vm.prank(alice);
        uint256 sharesMinted = vault.mint(mintAmount, alice);

        // Should mint 0 shares for 0 mint amount
        assertEq(sharesMinted, 0, "Should mint 0 shares for 0 mint");

        // Vault should not receive any tokens
        assertEq(weth.balanceOf(address(vault)), 0, "Vault should not receive WETH for 0 mint");

        // Alice's WETH should remain unchanged
        assertEq(weth.balanceOf(alice), initialWethBalance, "Alice's WETH balance should not change");

        // Alice's vault token balance should remain unchanged
        assertEq(vault.balanceOf(alice), 0, "Alice's share balance should not change");

        // totalAssets should not change
        assertEq(vault.totalAssets(), 0, "Vault's total assets should not change for 0 mint");

        assertEq(vault.convertToShares(1e18), 1e18, "Conversion to shares did not reflect mint");

        if (!alwaysComputeTotalAssets) {
            vault.processAccounting();
            assertEq(vault.totalAssets(), 0, "Vault's total assets should not change for 0 mint");
            assertEq(vault.balanceOf(alice), 0, "Alice's share balance should not change");
            assertEq(weth.balanceOf(address(vault)), 0, "Vault should not receive WETH for 0 mint");
            assertEq(weth.balanceOf(alice), initialWethBalance, "Alice's WETH balance should not change");
            assertEq(vault.convertToShares(0), 0, "Conversion to shares did not reflect 0 mint");

            assertEq(vault.convertToShares(1e18), 1e18, "Conversion to shares did not reflect mint");
        }
    }

    function test_Vault_mint_post_initial_deposit_and_donation(bool alwaysComputeTotalAssets) public {
        uint256 initialDeposit = 100 ether;
        uint256 donationAmount = 10 ether;
        uint256 mintAmount = 1 ether;

        HooksUtils.setPerformanceFee(vault, 0);

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        // Alice does an initial deposit
        vm.prank(alice);
        uint256 initShares = vault.deposit(initialDeposit, alice);

        // Simulate a donation (send tokens directly to vault)
        deal(address(weth), address(this), donationAmount);
        weth.transfer(address(vault), donationAmount);

        if (!alwaysComputeTotalAssets) {
            vault.processAccounting();
            assertEq(
                vault.totalAssets(), initialDeposit + donationAmount, "Total assets should reflect deposit + donation"
            );
        }

        // Total assets should increase by donationAmount, but total supply is unchanged
        assertEq(vault.totalAssets(), initialDeposit + donationAmount, "Total assets should reflect deposit + donation");
        assertEq(vault.totalSupply(), initShares, "Total supply should only reflect deposited shares");

        // Let's check what assets are now needed to mint 1 ether shares -- expected proportionally less due to donation
        uint256 requiredAssetsToMintNext = vault.previewMint(mintAmount);
        assertGt(requiredAssetsToMintNext, mintAmount, "Required assets should increase post-donation");

        // Bob mints 1 ether worth of shares
        address bob = address(0xB0B);
        deal(address(weth), bob, requiredAssetsToMintNext);
        vm.startPrank(bob);
        weth.approve(address(vault), requiredAssetsToMintNext);
        vault.mint(mintAmount, bob);
        vm.stopPrank();

        // Now check total supply and asset balances
        assertEq(vault.totalSupply(), initShares + mintAmount, "Total supply should reflect mint + deposit");
        assertEq(
            vault.totalAssets(),
            initialDeposit + donationAmount + requiredAssetsToMintNext,
            "Total assets should include donation and second deposit"
        );

        // Check Alice's and Bob's share proportions; Alice should have a larger proportion due to donation's dilution
        // Alice's proportion should be: initShares / (initShares + mintAmount)
        // Bob's: mintAmount / (initShares + mintAmount)
        // The total asset value that Alice could redeem should be larger than the initial deposit due to the donation

        uint256 aliceAssets = vault.previewRedeem(initShares);
        assertGt(aliceAssets, initialDeposit, "Alice's asset value should increase due to donation");
    }

    function test_Vault_previewMint(uint256 shares, bool alwaysComputeTotalAssets) public {
        if (shares < 10) return;
        if (shares > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 assets = vault.previewMint(shares);
        assertEq(assets, shares, "Preview mint does not match expected assets");
    }

    function test_Vault_previewMint_1_wei() public {
        uint256 shares = 1 wei;
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, 1 wei, "Preview mint does not match expected assets");
    }

    function test_Vault_maxMint_whenPaused_shouldRevert() public {
        // Pause the vault
        vm.prank(PAUSER);
        vault.pause();

        // Expect revert when calling maxMint while paused
        assertEq(vault.maxMint(alice), 0, "Should be zero when paused");
    }

    function test_Vault_maxMint() public view {
        uint256 maxMint = vault.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "Max mint does not match");
    }

    function test_Vault_mintWhilePaused() public {
        vm.prank(PAUSER);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1000, alice);
    }

    function test_Vault_mint_reverts_when_not_enough_assets(bool alwaysComputeTotalAssets) public {
        uint256 mintAmount = 1 ether;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        vm.startPrank(alice);
        weth.approve(address(vault), 0);
        vm.expectRevert();
        vault.mint(mintAmount, alice);
        vm.stopPrank();
    }
}
