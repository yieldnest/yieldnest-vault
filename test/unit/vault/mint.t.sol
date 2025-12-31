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

        vm.stopPrank();
    }

    function test_Vault_previewMint(uint256 shares, bool alwaysComputeTotalAssets) public {
        if (shares < 10) return;
        if (shares > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 assets = vault.previewMint(shares);
        assertEq(assets, shares, "Preview mint does not match expected assets");
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
}
