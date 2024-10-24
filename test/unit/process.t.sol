// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IERC20} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {MockSTETH} from "test/mocks/MockSTETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";

contract VaultProcessUnitTest is Test, MainnetContracts, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth,) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function skip_test_Vault_processAccounting_idleAssets() public {
        // Simulate some asset and strategy balances
        deal(alice, 200 ether); // Simulate some ether balance for the vault
        weth.deposit{value: 100 ether}(); // Deposit ether into WETH
        steth.deposit{value: 100 ether}(); // Mint some STETH

        // Set up some initial balances for assets and strategies
        vm.prank(alice);
        weth.transfer(address(vault), 50 ether); // Transfer some WETH to the vault
        steth.transfer(address(vault), 50 ether); // Transfer some STETH to the vault

        // Process accounting to update deployed assets
        vault.processAccounting();

        // Check that the deployed assets are updated correctly
        assertEq(vault.getAsset(address(weth)).idleAssets, 50 ether, "WETH deployed assets not updated correctly");
        assertEq(vault.getAsset(address(steth)).idleAssets, 50 ether, "STETH deployed assets not updated correctly");
    }
}
