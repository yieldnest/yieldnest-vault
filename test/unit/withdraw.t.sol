// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";

contract VaultWithdrawUnitTest is Test, MainnetContracts, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth,) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_previewWithdraw(uint256 assets) external view {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;
        uint256 amount = vault.previewWithdraw(assets);
        assertEq(amount, assets);
    }

    function test_Vault_withdraw(uint256 assets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.startPrank(alice);
        uint256 depositShares = vault.deposit(assets, alice);
        uint256 previewAmount = vault.previewWithdraw(assets);
        uint256 shares = vault.withdraw(assets, alice, alice);

        assertEq(previewAmount, shares, "Preview withdraw amount not preview amount");
        assertEq(depositShares, shares, "Deposit shares not match with withdraw shares");
    }

    function test_Vault_previewRedeem(uint256 shares) external view {
        if (shares < 2) return;
        if (shares > 100_000 ether) return;
        uint256 assets = vault.previewWithdraw(shares);
        assertEq(assets, shares, "Preview Assets response not shares");
    }

    function test_Vault_redeem(uint256 shares) external {
        if (shares < 2) return;
        if (shares > 100_000 ether) return;

        vm.startPrank(alice);
        uint256 depositShares = vault.deposit(shares, alice);
        uint256 previewAmount = vault.previewWithdraw(shares);
        uint256 sharesAfter = vault.withdraw(shares, alice, alice);

        assertEq(previewAmount, sharesAfter, "Preview redeem amount not preview amount");
        assertEq(depositShares, sharesAfter, "Deposit shares not match with redeem shares");
    }
}
