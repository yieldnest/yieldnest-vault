// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vault} from "src/Vault.sol";
import {ProxyAdmin} from "src/Common.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {VaultUtils} from "script/VaultUtils.sol";


contract YnBNBxForkTest is Test, MainnetActors, ProxyUtils, VaultUtils {
    Vault public vault;
    IERC20 public wbnb;

    function setUp() public {
        
        vault = Vault(payable(MainnetContracts.YNBNBX));
        wbnb = IERC20(MainnetContracts.WBNB);

        {
            // Set approval rules for WBNB
            vm.startPrank(ProxyAdmin(getProxyAdmin(address(vault))).owner());

            address[] memory spenders = new address[](2);
            spenders[0] = MainnetContracts.YNCLISBNBK;
            spenders[1] = MainnetContracts.YNWBNBK;

            setApprovalRule(vault, MainnetContracts.WBNB, spenders);

            vm.stopPrank();
        }
    }

    function testDepositAndStake() public {
        address alice = address(0xABCD);
        uint256 depositAmount = 1000 ether;

        // Give alice some WBNB
        deal(address(wbnb), alice, depositAmount);

        vm.startPrank(alice);

        // Approve vault to spend WBNB
        wbnb.approve(address(vault), depositAmount);

        // Initial balances
        uint256 aliceWBNBBefore = wbnb.balanceOf(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        console.log("Alice WBNB balance before:", aliceWBNBBefore);
        console.log("Alice shares before:", aliceSharesBefore);

        // Deposit WBNB to get shares
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(wbnb.balanceOf(alice), aliceWBNBBefore - depositAmount, "WBNB balance incorrect");
        assertGt(vault.balanceOf(alice), aliceSharesBefore, "Should have received shares");

        // Check vault state after deposit
        assertEq(vault.totalAssets(), depositAmount, "Total assets should match deposit amount");
        assertEq(vault.totalSupply(), depositAmount, "Total supply should match deposit amount"); 


        // Check that vault has WBNB balance
        assertEq(wbnb.balanceOf(address(vault)), depositAmount, "Vault should have WBNB balance");


        // Create approval calldata
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            MainnetContracts.YNCLISBNBK,
            depositAmount
        );

        // Create deposit calldata
        bytes memory depositCalldata = abi.encodeWithSignature(
            "deposit(uint256,address)",
            depositAmount,
            address(vault)
        );

        {
            // Set up arrays for processor call
            address[] memory targets = new address[](2);
            targets[0] = MainnetContracts.WBNB;
            targets[1] = MainnetContracts.YNCLISBNBK;

            uint256[] memory values = new uint256[](2);
            values[0] = 0;
            values[1] = 0;

            bytes[] memory data = new bytes[](2);
            data[0] = approveCalldata;
            data[1] = depositCalldata;
            // Store initial state
            uint256 totalAssetsBefore = vault.totalAssets();
            uint256 totalSupplyBefore = vault.totalSupply();

            // Process transactions through processor
            vm.prank(PROCESSOR);
            vault.processor(targets, values, data);

            // Verify WBNB was transferred to clisBNB
            assertEq(wbnb.balanceOf(address(vault)), 0, "Vault should have 0 WBNB after deposit");
            assertEq(IERC20(MainnetContracts.YNCLISBNBK).balanceOf(address(vault)), depositAmount, "Vault should have received ynClisBNBk tokens");

            // Verify total assets and supply remain unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }

        {
            // Define withdrawal amount
            uint256 withdrawAmount = depositAmount / 2;

            // Create withdrawal calldata to unstake half the amount
            bytes memory withdrawCalldata = abi.encodeWithSignature(
                "withdraw(uint256,address,address)",
                withdrawAmount,
                address(vault),
                address(vault)
            );

            // Set up arrays for processor call to unstake
            address[] memory targets = new address[](1);
            targets[0] = MainnetContracts.YNCLISBNBK;

            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            bytes[] memory data = new bytes[](1);
            data[0] = withdrawCalldata;

            // Store state before unstaking
            uint256 totalAssetsBefore = vault.totalAssets();
            uint256 totalSupplyBefore = vault.totalSupply();

            // Process unstaking through processor
            vm.prank(PROCESSOR);
            vault.processor(targets, values, data);

            // Verify half of ynClisBNBk was unstaked back to WBNB
            assertEq(wbnb.balanceOf(address(vault)), withdrawAmount, "Vault should have received half WBNB back");
            assertEq(IERC20(MainnetContracts.YNCLISBNBK).balanceOf(address(vault)), withdrawAmount, "Vault should have half ynClisBNBk remaining");

            // Verify total assets and supply remain unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }
    }

    function testDepositAllocateToBufferAndWithdraw() public {
        address alice = address(0xABCD);
        uint256 depositAmount = 1 ether;

        // Initial deposit
        // Give alice some WBNB
        deal(address(wbnb), alice, depositAmount);
        vm.startPrank(alice);
        wbnb.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify initial state
        assertEq(vault.totalSupply(), depositAmount, "Initial total supply should match deposit");
        assertEq(wbnb.balanceOf(address(vault)), depositAmount, "Vault should have WBNB balance");

        // Create approval calldata for buffer
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            MainnetContracts.YNWBNBK,
            depositAmount
        );

        // Create deposit calldata for buffer
        bytes memory depositCalldata = abi.encodeWithSignature(
            "deposit(uint256,address)",
            depositAmount,
            address(vault)
        );

        // Set up arrays for processor call to deposit to buffer
        address[] memory targets = new address[](2);
        targets[0] = MainnetContracts.WBNB;
        targets[1] = MainnetContracts.YNWBNBK;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = approveCalldata;
        data[1] = depositCalldata;

        // Store state before buffer allocation
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Process deposit to buffer
        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Verify WBNB was transferred to buffer
        assertEq(wbnb.balanceOf(address(vault)), 0, "Vault should have 0 WBNB after buffer deposit");
        assertEq(IERC20(MainnetContracts.YNWBNBK).balanceOf(address(vault)), depositAmount, "Vault should have received ynWBNBk tokens");
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");

        // Now test withdrawal
        vm.startPrank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();

        // Verify final state after withdrawal
        assertEq(vault.totalSupply(), 0, "Total supply should be 0 after withdrawal");
        assertApproxEqRel(wbnb.balanceOf(alice), depositAmount, 1e15, "Alice should have received WBNB");
        assertEq(IERC20(MainnetContracts.YNWBNBK).balanceOf(address(vault)), depositAmount - wbnb.balanceOf(alice), "Vault's ynWBNBk balance should equal deposit minus withdrawal");
    }

    function testUpgradeVaultWithTimelock() public {
        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(address(vault)));

        // Verify timelock ownership
        assertEq(proxyAdmin.owner(), 0x437794E1142bB2B6C2E3a90fc778c297ea8BF9Aa);

        // Deploy new implementation
        Vault newImplementation = new Vault();

  
        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData = abi.encodeWithSelector(
            proxyAdmin.upgradeAndCall.selector,
            address(vault), 
            address(newImplementation),
            ""
        );

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(
            address(proxyAdmin),
            0,
            upgradeData, 
            bytes32(0),
            bytes32(0),
            timelock.getMinDelay()
        );
        vm.stopPrank();

        // Wait for timelock delay
        vm.warp(block.timestamp + timelock.getMinDelay());

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(
            address(proxyAdmin),
            0,
            upgradeData,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();
        // Verify upgrade was successful
        assertEq(getImplementation(address(vault)), address(newImplementation), "Implementation address should match new implementation");
    }
}
