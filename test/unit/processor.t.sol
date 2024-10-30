// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IERC20} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";
import {MockSTETH} from "test/mocks/MockST_ETH.sol";

contract VaultProcessUnitTest is Test, MainnetContracts, MainnetActors, Etches {
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
        steth = MockSTETH(payable(STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_processAccounting_idleAssets() public {
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
        assertEq(vault.getAsset(address(weth)).idleBalance, 50 ether, "WETH balance not updated correctly");
        assertEq(vault.getAsset(address(steth)).idleBalance, 50 ether, "STETH balance not updated correctly");
    }

    function test_Vault_processor_fails_with_invalid_asset_approve() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(420);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(vault), 50 ether);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_with_invalid_asset_transfer() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(weth);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", address(vault), 50 ether);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }
}
