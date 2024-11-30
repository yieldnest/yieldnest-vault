// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {TestPlugin} from "test/unit/helpers/TestPlugin.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";

contract VaultProcessUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;
    TestPlugin public plugin;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth, plugin) = setupVault.setup();

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

    function test_Vault_processAccounting_idleAssets() public {
        // Simulate some asset and strategy balances
        deal(alice, 200 ether); // Simulate some ether balance for the vault
        weth.deposit{value: 100 ether}(); // Deposit ether into WETH
        steth.deposit{value: 100 ether}(); // Mint some STETH

        // Set up some initial balances for assets and strategies
        vm.prank(alice);
        weth.transfer(address(vault), 50 ether); // Transfer some WETH to the vault
        steth.transfer(address(vault), 50 ether); // Transfer some STETH to the vault

        vault.processAccounting();
    }

    function test_Vault_processor_fails_with_invalid_plugin() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(420);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_with_invalid_asset_approve() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(plugin);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] =
            abi.encodeWithSignature("approveToken(address,address,uint256)", address(420), address(vault), 50 ether);

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
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
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_ValueAboveMaximum() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(plugin);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature(
            "depositIntoVault(address,uint256,address)", address(MC.YNETH), 100_001 ether, address(vault)
        );

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_ValueBelowMinimum() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(plugin);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] =
            abi.encodeWithSignature("depositIntoVault(address,uint256,address)", address(MC.YNETH), 1, address(vault));

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processor_fails_AddressNotInAllowlist() public {
        // Set up some initial balances for assets and strategies

        // Prepare allocation targets and values
        address[] memory targets = new address[](1);
        targets[0] = address(plugin);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] =
            abi.encodeWithSignature("depositIntoVault(address,uint256,address)", address(MC.YNETH), 100, address(420));

        // Expect the processAllocation to fail with an invalid asset
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_isTargetWhitelisted() public view {
        assertTrue(vault.isTargetWhitelisted(address(plugin)));
        assertFalse(vault.isTargetWhitelisted(address(420)));
    }

    function test_Vault_processorCall_failsWithBadTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0); // Invalid target address

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 100, address(420));

        // Expect the processor call to fail with an invalid target
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }

    function test_Vault_processorCall_failsWithBadCalldata() public {
        // make sure the processor rule has been set

        address[] memory targets = new address[](1);
        targets[0] = address(plugin);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", 10000000 ether, address(vault)); // Invalid function signature

        // Expect the processor call to fail with and send return data
        vm.prank(PROCESSOR);
        vm.expectRevert();
        vault.processor(targets, values, data);
    }
}
