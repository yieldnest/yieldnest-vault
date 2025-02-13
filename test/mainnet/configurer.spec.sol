```solidity
// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHx} from "src/YnETHx.sol";
import {IVault} from "src/interface/IVault.sol";

import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";

import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

contract VaultConfigureUpgradeTest is Test, MainnetActors {
    function test_configure() public {
        Vault vault = Vault(payable(MC.YNETHX));
        Withdrawer withdrawer;
        uint256 previousTotalAssets = vault.totalAssets();
        TimelockController timelock = TimelockController(payable(MC.TIMELOCK));

        {
            vm.expectRevert();
            vault.VAULT_VERSION();
        }

        {
            // upgrade the vault
            Vault vaultImpl = Vault(payable(new YnETHx()));

            // schedule a proxy upgrade transaction on the timelock
            // the traget is the proxy admin for the max Vault Proxy Contract
            address target = MC.PROXY_ADMIN;
            uint256 value = 0;

            bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

            bytes memory initData = abi.encodeWithSelector(YnETHx.initializeV2.selector, 18, 0);
            bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(vaultImpl), initData);

            bytes32 predecessor = bytes32(0);
            bytes32 salt = keccak256("chad");

            uint256 delay = 86400;

            vm.startPrank(PROPOSER_1);
            timelock.schedule(target, value, data, predecessor, salt, delay);
            vm.stopPrank();

            bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
            assert(timelock.getOperationState(id) == TimelockController.OperationState.Waiting);

            assertEq(timelock.isOperationReady(id), false);
            assertEq(timelock.isOperationDone(id), false);
            assertEq(timelock.isOperation(id), true);

            //execute the transaction
            // solhint-disable-next-line not-rely-on-time
            vm.warp(block.timestamp + 86401);
            vm.startPrank(EXECUTOR_1);
            timelock.execute(target, value, data, predecessor, salt);
            vm.stopPrank();

            // Verify the transaction was executed successfully
            assertEq(timelock.isOperationReady(id), false);
            assertEq(timelock.isOperationDone(id), true);
            assert(timelock.getOperationState(id) == TimelockController.OperationState.Done);
        }

        {
            // configure the vault
            Vault newVault = Vault(payable(MC.YNETHX));

            assertEq(newVault.symbol(), "ynETHx");

            assertTrue(newVault.paused(), "Vault should be paused");

            YnETHxConfigurer configurer = new YnETHxConfigurer();
            SetupWithdrawer setup = new SetupWithdrawer();
            withdrawer = setup.setup();
            Provider provider = new Provider();

            vm.startPrank(ADMIN);
            newVault.grantRole(newVault.DEFAULT_ADMIN_ROLE(), address(configurer));

            configurer.configure(address(provider), address(withdrawer));
            vm.stopPrank();
        }

        {
            // verify the upgrade was successful
            Vault newVault = Vault(payable(MC.YNETHX));

            assertFalse(newVault.paused(), "Vault should not be paused");

            newVault.processAccounting();

            // Verify the upgrade was successful
            uint256 newTotalAssets = newVault.totalAssets();

            assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");
            assertEq(
                keccak256(bytes(vault.VAULT_VERSION())), keccak256(bytes("0.2.0")), "Vault version should be 0.1.2"
            );
        }

        IActors actors = IActors(payable(address(this)));

        VaultVerification.verifyProvider(Provider(IVault(address(vault)).provider()), withdrawer);

        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        VaultVerification.verifyRules(vault);

        // verify actors & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // verify proxy roles on vault
        RolesVerification.verifyProxyRoles(address(vault), MC.PROXY_ADMIN, address(timelock));

        // verify withdrawer config
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // verify withdrawer roles
        VaultVerification.verifyWithdrawerRules(withdrawer);

        // verify actors & timelock roles on withdrawer
        RolesVerification.verifyDefaultRoles(withdrawer, timelock, actors);
        RolesVerification.verifyRole(
            withdrawer, address(vault), withdrawer.ALLOCATOR_ROLE(), true, "YnETHx has ALLOCATOR_ROLE"
        );

        address withdrawerProxyAdmin = ProxyUtils.getProxyAdmin(address(withdrawer));

        // verify proxy roles on withdrawer
        RolesVerification.verifyProxyRoles(address(withdrawer), withdrawerProxyAdmin, address(timelock));

        // verify timelock roles
        uint256 minDelay = 1 days;
        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);
    }

    function test_deposit_ynETH() public {
        Vault vault = Vault(payable(MC.YNETHX));
        uint256 depositAmount = 10 ether;

        // Deposit ynETH
        deal(MC.YNETH, address(this), depositAmount);
        IERC20(MC.YNETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNETH, depositAmount, address(this));

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match deposit amount");
    }

    function test_deposit_ynLSDe() public {
        Vault vault = Vault(payable(MC.YNETHX));
        uint256 depositAmount = 10 ether;

        // Deposit ynLSDe
        deal(MC.YNLSDE, address(this), depositAmount);
        IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNLSDE, depositAmount, address(this));

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match deposit amount");
    }

    function test_deposit_wETH() public {
        Vault vault = Vault(payable(MC.YNETHX));
        uint256 depositAmount = 10 ether;

        // Deposit wETH
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match deposit amount");
    }

    function test_donate_whitelisted_assets() public {
        Vault vault = Vault(payable(MC.YNETHX));
        uint256 donationAmount = 1 ether;

        // Donate the 10 whitelisted assets to the vault
        address[] memory whitelistedAssets = new address[](10);
        whitelistedAssets[0] = MC.WETH;
        whitelistedAssets[1] = MC.YNETH;
        whitelistedAssets[2] = MC.YNLSDE;
        whitelistedAssets[3] = MC.STETH;
        whitelistedAssets[4] = MC.EULER_WETH_22_VAULT;
        whitelistedAssets[5] = MC.CURVE_LP_YNETH_YNLSDE_STRATEGY;
        whitelistedAssets[6] = MC.WSTETH;
        whitelistedAssets[7] = MC.OETH;
        whitelistedAssets[8] = MC.WOETH;
        whitelistedAssets[9] = MC.SMOKEHOUSE_WSTETH;

        for (uint256 i = 0; i < whitelistedAssets.length; i++) {
            deal(whitelistedAssets[i], address(this), donationAmount);
            IERC20(whitelistedAssets[i]).transfer(address(vault), donationAmount);
        }

        // Call processAccounting
        vault.processAccounting();

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();
        uint256 expectedTotalAssets = donationAmount * whitelistedAssets.length;
        assertEq(totalAssets, expectedTotalAssets, "Total assets should match donation amount");
    }

    function test_allocate_to_buffer_and_withdraw() public {
        Vault vault = Vault(payable(MC.YNETHX));
        uint256 depositAmount = 10 ether;
        uint256 bufferAmount = 5 ether;

        // Deposit wETH
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Allocate to buffer
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = vault.buffer();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), bufferAmount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", bufferAmount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Withdraw from buffer
        vault.withdraw(bufferAmount, address(this), address(this));

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount - bufferAmount, "Total assets should match deposit amount minus buffer amount");
    }

    function test_move_assets_to_withdrawer_and_process_accounting() public {
        Vault vault = Vault(payable(MC.YNETHX));
        Withdrawer withdrawer = Withdrawer(payable(MC.WITHDRAWER));
        uint256 depositAmount = 10 ether;

        // Deposit wETH
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Move assets to withdrawer
        address[] memory targets = new address[](1);
        targets[0] = address(withdrawer);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", depositAmount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        // Call processAccounting on withdrawer
        withdrawer.processAccounting();

        // Assert totalAssets is correct
        uint256 totalAssets = withdrawer.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match deposit amount");
    }
}
```
