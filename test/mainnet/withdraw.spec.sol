// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, TransparentUpgradeableProxy, IERC4626, Math} from "src/Common.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";

contract VaultWithdrawTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    IProvider public provider;

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_Vault_maxWithdraw_reverts() public {
        address alice = address(0x1);

        // First deposit some assets to have a valid owner with shares
        deal(MC.USDC, alice, 1000e6);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        // Now test maxWithdraw with valid owner parameter
        vm.expectRevert();
        vault.maxWithdraw(alice);
    }

    function test_Vault_maxRedeem_reverts() public {
        address alice = address(0x1);

        // First deposit some assets to have a valid owner with shares
        deal(MC.USDC, alice, 1000e6);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        // Now test maxRedeem with valid owner parameter
        vm.expectRevert();
        vault.maxRedeem(alice);
    }

    function test_Vault_withdraw_reverts() public {
        address alice = address(0x1);

        // First deposit some assets to have a valid owner with shares
        deal(MC.USDC, alice, 1000e6);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        // Now test withdraw reverts
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(500e6, alice, alice);
    }

    function test_Vault_redeem_reverts() public {
        address alice = address(0x1);

        // First deposit some assets to have a valid owner with shares
        deal(MC.USDC, alice, 1000e6);
        vm.prank(alice);
        IERC20(MC.USDC).approve(address(vault), 1000e6);
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);

        // Now test redeem reverts
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares / 2, alice, alice);
    }
}
