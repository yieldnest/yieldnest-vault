// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Vault} from "src/Vault.sol";
import {ProxyAdmin, Math} from "src/Common.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Vault} from "src/Vault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";
import {HooksUtils} from "test/utils/HooksUtils.sol";

contract YnBNBxForkTest is BaseIntegrationTest {
    IERC20 public wbnb;

    function setUp() public virtual override {
        super.setUp();
        wbnb = IERC20(MainnetContracts.WBNB);
    }

    function testDepositAndStake() public {
        unpauseKernelVaultsDeposit(MainnetContracts.CLISBNB);

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

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault WBNB balance
        uint256 vaultWBNBBefore = wbnb.balanceOf(address(vault));

        // Deposit WBNB to get shares
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Check balances after deposit
        assertEq(wbnb.balanceOf(alice), aliceWBNBBefore - depositAmount, "WBNB balance incorrect");
        assertGt(vault.balanceOf(alice), aliceSharesBefore, "Should have received shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets + depositAmount, "Total assets should increase by deposit amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by deposit amount");

        // Check that vault WBNB balance increased by deposit amount
        assertEq(
            wbnb.balanceOf(address(vault)),
            vaultWBNBBefore + depositAmount,
            "Vault WBNB balance should increase by deposit"
        );

        {
            // Store initial state
            uint256 totalAssetsBefore = vault.totalAssets();
            uint256 totalSupplyBefore = vault.totalSupply();

            _processorDepositToERC4626(MainnetContracts.YNCLISBNBK, depositAmount);

            uint256 clisBNBShares = IERC4626(MainnetContracts.YNCLISBNBK).convertToShares(depositAmount);

            // Verify WBNB was transferred to clisBNB
            assertEq(
                wbnb.balanceOf(address(vault)), vaultWBNBBefore, "Vault should have vaultWBNBBefore WBNB after deposit"
            );
            assertEq(
                IERC20(MainnetContracts.YNCLISBNBK).balanceOf(address(vault)),
                clisBNBShares,
                "Vault should have received ynClisBNBk tokens"
            );

            // Verify total assets and supply remain unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }

        {
            // Define withdrawal amount
            uint256 withdrawAmount = depositAmount / 2;

            // Create withdrawal calldata to unstake half the amount
            bytes memory withdrawCalldata = abi.encodeWithSignature(
                "withdraw(uint256,address,address)", withdrawAmount, address(vault), address(vault)
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
            uint256 clisBNBSharesBefore = IERC20(MainnetContracts.YNCLISBNBK).balanceOf(address(vault));

            // Process unstaking through processor
            vm.prank(PROCESSOR);
            vault.processor(targets, values, data);

            uint256 clisBNBShares = IERC4626(MainnetContracts.YNCLISBNBK).convertToShares(withdrawAmount);

            // Verify half of ynClisBNBk was unstaked back to WBNB
            assertEq(
                wbnb.balanceOf(address(vault)),
                vaultWBNBBefore + withdrawAmount,
                "Vault should have received half WBNB back"
            );
            assertEq(
                IERC20(MainnetContracts.YNCLISBNBK).balanceOf(address(vault)),
                clisBNBSharesBefore - clisBNBShares,
                "Vault should have half ynClisBNBk remaining"
            );

            // Verify total assets and supply remain unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }
    }

    function testDepositAllocateToBufferAndWithdraw() public {
        address alice = address(0xABCD);
        uint256 depositAmount = 1 ether;

        uint256 initialWBNBBalance = wbnb.balanceOf(address(vault));
        uint256 initialSupply = vault.totalSupply();
        uint256 initialAssets = vault.totalAssets();
        {
            // Initial deposit
            // Give alice some WBNB
            deal(address(wbnb), alice, depositAmount);
            vm.startPrank(alice);
            wbnb.approve(address(vault), depositAmount);
            uint256 shares = vault.deposit(depositAmount, alice);
            vm.stopPrank();

            // Verify initial state
            assertEq(vault.totalSupply(), initialSupply + shares, "Total supply should match deposit");
            assertEq(vault.totalAssets(), initialAssets + depositAmount, "Total assets should match deposit");
            assertEq(
                wbnb.balanceOf(address(vault)), initialWBNBBalance + depositAmount, "Vault should have WBNB balance"
            );
        }

        // Store state before buffer allocation
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        address buffer = vault.buffer();

        uint256 beforeBufferBalance = IERC20(buffer).balanceOf(address(vault));

        // Process deposit to buffer
        _processorDepositToERC4626(buffer, depositAmount);

        uint256 bufferShares = IERC4626(buffer).convertToShares(depositAmount);

        // Verify WBNB was transferred to buffer
        assertEq(
            wbnb.balanceOf(address(vault)),
            initialWBNBBalance,
            "Vault should have initial WBNB balance after buffer deposit"
        );
        assertEq(
            IERC20(buffer).balanceOf(address(vault)),
            beforeBufferBalance + bufferShares,
            "Vault should have received shares"
        );
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 2, "Total assets should remain unchanged");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");

        // Now test withdrawal
        vm.startPrank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();

        // Verify final state after withdrawal
        assertEq(vault.totalSupply(), initialSupply, "Total supply should be initialSupply after withdrawal");
        assertApproxEqRel(wbnb.balanceOf(alice), depositAmount, 1e15, "Alice should have received WBNB");
    }

    function testUpgradeVaultWithTimelock(address vaultAddress, Vault newImplementation) internal {
        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(vaultAddress));

        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData =
            abi.encodeWithSelector(proxyAdmin.upgradeAndCall.selector, vaultAddress, address(newImplementation), "");

        uint256 delay = 86400;

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0), delay);
        vm.stopPrank();

        // Wait for timelock delay
        vm.warp(block.timestamp + delay);

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0));
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(
            ProxyUtils.getImplementation(vaultAddress),
            address(newImplementation),
            "Implementation address should match new implementation"
        );
    }

    function testUpgradeYnBNBxWithTimelock() public {
        Vault newImplementation = new Vault();
        testUpgradeVaultWithTimelock(address(vault), newImplementation);
    }

    function testUpgradeYnwbnbkWithTimelock() public {
        Vault newImplementation = new Vault();
        testUpgradeVaultWithTimelock(MainnetContracts.YNWBNBK, newImplementation);
    }

    function testUpgradeYnclisBNBkWithTimelock() public {
        Vault newImplementation = new Vault();
        testUpgradeVaultWithTimelock(MainnetContracts.YNCLISBNBK, newImplementation);
    }

    function testAddRoleAndActivateAsset() public {
        // Grant ASSET_MANAGER_ROLE to alice
        bytes32 ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
        address alice = makeAddr("alice");

        // Grant role directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(ASSET_MANAGER_ROLE, alice);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(vault.hasRole(ASSET_MANAGER_ROLE, alice), "Alice should have asset manager role");

        vm.startPrank(alice);
        vault.updateAsset(1, IVault.AssetUpdateFields({active: true}));
        vm.stopPrank();

        // Get asset at index 1
        address assetAtIndex = vault.getAssets()[1];

        // Get asset params and verify active status
        IVault.AssetParams memory params = vault.getAsset(assetAtIndex);
        assertTrue(params.active, "Asset should be active");
        assertEq(assetAtIndex, MainnetContracts.YNWBNBK, "Asset at index 1 should be YNWBNBK");
    }

    function testAddRoleAndActivateYnwbnbk() public {
        // Grant ASSET_MANAGER_ROLE to alice
        address alice = makeAddr("alice");

        Vault ynwbnbk = Vault(payable(MainnetContracts.YNWBNBK));
        // Grant roles directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        bytes32 FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

        ynwbnbk.grantRole(FEE_MANAGER_ROLE, alice);
        vm.stopPrank();

        assertTrue(ynwbnbk.hasRole(FEE_MANAGER_ROLE, alice), "Alice should have fee manager role");

        // Set base withdrawal fee to 50 basis points (0.5%)
        uint64 newFee = 50_000; // 50_000 = 0.5% (1e8 = 100%)
        vm.startPrank(alice);
        ynwbnbk.setBaseWithdrawalFee(newFee);
        vm.stopPrank();

        // Verify fee was set correctly
        assertEq(ynwbnbk.baseWithdrawalFee(), newFee, "Base withdrawal fee should be set to 0.5%");
    }

    function testAddRoleAndActivateYnclisbnbk() public {
        // Grant ASSET_MANAGER_ROLE to alice
        address alice = makeAddr("alice");

        Vault ynclisbnbk = Vault(payable(MainnetContracts.YNCLISBNBK));
        // Grant roles directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        bytes32 FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

        ynclisbnbk.grantRole(FEE_MANAGER_ROLE, alice);
        vm.stopPrank();

        assertTrue(ynclisbnbk.hasRole(FEE_MANAGER_ROLE, alice), "Alice should have fee manager role");

        // Set base withdrawal fee to 50 basis points (0.5%)
        uint64 newFee = 50_000; // 50_000 = 0.5% (1e8 = 100%)
        vm.startPrank(alice);
        ynclisbnbk.setBaseWithdrawalFee(newFee);
        vm.stopPrank();

        // Verify fee was set correctly
        assertEq(ynclisbnbk.baseWithdrawalFee(), newFee, "Base withdrawal fee should be set to 0.5%");
    }

    function testDirectDepositToStrategiesShouldRevert() public {
        address alice = makeAddr("alice");
        uint256 depositAmount = 1000 ether;

        // Give alice some WBNB
        deal(address(wbnb), alice, depositAmount);

        vm.startPrank(alice);
        wbnb.approve(MainnetContracts.YNWBNBK, depositAmount);
        wbnb.approve(MainnetContracts.YNCLISBNBK, depositAmount);

        // Try to deposit directly to buffer strategy (ynWBNBk)
        vm.expectRevert();
        IERC20(MainnetContracts.YNWBNBK).transfer(address(0), depositAmount);

        // Try to deposit directly to ynClisBNBk strategy
        vm.expectRevert();
        IERC20(MainnetContracts.YNCLISBNBK).transfer(address(0), depositAmount);

        vm.stopPrank();
    }

    function testDonateToVault() public {
        HooksUtils.setMaxTotalAssetsIncreaseRatio(vault, 1 ether);
        HooksUtils.setMaxTotalSupplyIncreaseRatio(vault, 1 ether);

        address alice = makeAddr("alice");
        uint256 depositAmount = 100 ether;
        uint256 donationAmount = 10 ether;

        // Give alice some WBNB
        deal(address(wbnb), alice, depositAmount);

        vm.startPrank(alice);

        // Approve and deposit WBNB
        wbnb.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);

        vm.stopPrank();

        // Record balances before donation
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultSharesBefore = vault.totalSupply();
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Create bob and give him BNB
        address bob = makeAddr("bob");
        vm.deal(bob, donationAmount);

        // Switch to bob to donate
        vm.startPrank(bob);

        // Donate native BNB to vault
        (bool success,) = address(vault).call{value: donationAmount}("");
        assertTrue(success, "BNB donation failed");

        uint256 performanceFeeReceiverBalanceBefore =
            address(vault.hooks()) != address(0) ? ViewUtils.getPerformanceFeeReceiverBalance(vault) : 0;

        vm.stopPrank();

        vault.processAccounting();

        uint256 performanceFeeSharesMinted = 0;
        if (address(vault.hooks()) != address(0)) {
            uint256 performanceFeeReceiverBalanceAfter = ViewUtils.getPerformanceFeeReceiverBalance(vault);

            performanceFeeSharesMinted = performanceFeeReceiverBalanceAfter - performanceFeeReceiverBalanceBefore;
            uint256 performanceFee = ViewUtils.getPerformanceFee(vault) * donationAmount / 1e18;

            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeSharesMinted),
                performanceFee,
                2,
                "Performance fee assets should be equal to donation amount"
            );
            // Verify donation increased total assets but not shares
            assertEq(
                vault.totalAssets(), vaultAssetsBefore + donationAmount, "Total assets should increase by donation"
            );
        }

        assertEq(
            vault.totalSupply(),
            vaultSharesBefore + performanceFeeSharesMinted,
            "Total supply should increase by performance fee shares"
        );

        assertEq(vault.balanceOf(alice), aliceSharesBefore, "Alice's shares should remain unchanged");

        // Verify rate increased due to donation
        uint256 newRate = vault.convertToAssets(1e18);
        uint256 expectedRate =
            ((vaultAssetsBefore + donationAmount) * 1e18) / (vaultSharesBefore + performanceFeeSharesMinted);
        assertApproxEqAbs(newRate, expectedRate, 1, "New rate should reflect donation");
    }

    function testDonateToBufferWithoutWithdrawal() public {
        unpauseKernelVaultsDeposit(MainnetContracts.WBNB);
        unpauseKernelVaultsDeposit(MainnetContracts.CLISBNB);

        address alice = makeAddr("alice");
        uint256 depositAmount = 100 ether;
        uint256 bufferAmount = depositAmount / 10; // 10% to buffer
        uint256 investAmount = depositAmount / 5;
        uint256 donationAmount = 1 ether;

        // Give alice some WBNB
        deal(address(wbnb), alice, depositAmount);

        vm.startPrank(alice);

        // Approve and deposit WBNB
        wbnb.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);

        vm.stopPrank();

        {
            // Store initial state
            uint256 totalAssetsBefore = vault.totalAssets();
            uint256 totalSupplyBefore = vault.totalSupply();

            _processorDepositToERC4626(MainnetContracts.YNWBNBK, bufferAmount);

            // Verify total assets unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            // Verify total supply unchanged
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }

        {
            // Store initial state
            uint256 totalAssetsBefore = vault.totalAssets();
            uint256 totalSupplyBefore = vault.totalSupply();

            _processorDepositToERC4626(MainnetContracts.YNCLISBNBK, investAmount);

            // Verify total assets unchanged
            assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
            // Verify total supply unchanged
            assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        }

        // Record state before donation
        uint256 bufferBefore = IERC4626(vault.buffer()).totalAssets();
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultSharesBefore = vault.totalSupply();
        uint256 oldRate = vault.convertToAssets(1e18);

        // Record buffer shares in vault before donation
        uint256 bufferSharesBefore = IERC4626(vault.buffer()).balanceOf(address(vault));
        uint256 bufferTotalSupplyBefore = IERC4626(vault.buffer()).totalSupply();

        uint256 bufferRateBefore = IERC4626(vault.buffer()).convertToAssets(1e18);

        {
            // Create bob and give him WBNB for donation
            address bob = makeAddr("bob");
            deal(address(wbnb), bob, donationAmount);

            // Bob transfers WBNB directly to buffer
            vm.startPrank(bob);
            wbnb.transfer(address(vault.buffer()), donationAmount);
            vm.stopPrank();
        }

        // Verify buffer assets not increased by donation
        assertEq(IERC4626(vault.buffer()).totalAssets(), bufferBefore, "Buffer should increase by donation");

        assertEq(
            IERC4626(vault.buffer()).totalSupply(),
            bufferTotalSupplyBefore,
            "Buffer total supply should remain unchanged"
        );

        assertEq(
            IERC4626(vault.buffer()).balanceOf(address(vault)),
            bufferSharesBefore,
            "Buffer shares should remain unchanged"
        );

        // Verify buffer rate increased due to donation
        uint256 bufferRateAfter = IERC4626(vault.buffer()).convertToAssets(1e18);

        assertEq(bufferRateAfter, bufferRateBefore, "Buffer rate should increase");

        // Verify total assets did not increase
        {
            assertApproxEqAbs(
                vault.totalAssets(),
                vaultAssetsBefore,
                1,
                "Total assets should increase proportionally to the shares held by the vault"
            );
            assertEq(vault.totalSupply(), vaultSharesBefore, "Total supply should remain unchanged");

            // Verify vault rate increased due to donation
            uint256 newRate = vault.convertToAssets(1e18);
            assertEq(newRate, oldRate, "New rate should increase");
        }
    }

    function testDonateToBufferAndWithdraw() public {
        address alice = address(0xABCD);
        uint256 depositAmount = 1 ether;

        // Initial deposit from alice
        deal(address(wbnb), alice, depositAmount);
        vm.startPrank(alice);
        wbnb.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Bob donates directly to buffer
        Vault buffer = Vault(payable(vault.buffer()));

        {
            address charlie = makeAddr("charlie");
            // Charlie deposits WBNB to buffer
            uint256 charlieAmount = 1 ether;
            // Give charlie some native BNB
            vm.deal(charlie, charlieAmount);

            vm.startPrank(charlie);
            deal(address(wbnb), charlie, charlieAmount);
            wbnb.approve(address(buffer), charlieAmount);
            buffer.deposit(charlieAmount, charlie);
            vm.stopPrank();
        }

        uint256 bufferTotalAssetsBefore = buffer.totalAssets();

        uint256 donationAmount = 200_000_000 ether;
        {
            // Create bob and give him WBNB for donation
            address bob = makeAddr("bob");
            deal(address(wbnb), bob, donationAmount);
            vm.startPrank(bob);
            wbnb.transfer(address(buffer), donationAmount);
            vm.stopPrank();
        }

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Verify buffer total assets stayed the same by donation
        assertEq(
            buffer.totalAssets(), bufferTotalAssetsBefore, "Buffer total assets should increase by donation amount"
        );

        // Process deposit to buffer
        _processorDepositToERC4626(address(buffer), depositAmount);

        // assets do not increase by donation since vault allocated to vault before
        assertApproxEqRel(vault.totalAssets(), initialTotalAssets, 1e9, "Total assets should not increase by donation");
        assertEq(vault.totalSupply(), initialTotalSupply, "Total supply should remain unchanged");
    }

    function _processorDepositToERC4626(address erc4626Token, uint256 depositAmount) public {
        // Set up arrays for processor call
        address[] memory targets = new address[](2);
        targets[0] = IERC4626(erc4626Token).asset();
        targets[1] = erc4626Token;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", erc4626Token, depositAmount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, address(vault));

        // Process transactions through processor
        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }
}
