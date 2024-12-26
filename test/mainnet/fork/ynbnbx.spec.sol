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



        {
            // Set approval rules for WBNB
            vm.startPrank(ProxyAdmin(getProxyAdmin(address(vault))).owner());

            address[] memory spenders = new address[](2);
            spenders[0] = MainnetContracts.YNCLISBNBK;
            spenders[1] = MainnetContracts.YNWBNBK;

            setApprovalRule(vault, MainnetContracts.WBNB, spenders);

            vm.stopPrank();
        }


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
