// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {IVault} from "src/interface/IVault.sol";

import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";

import {VaultVerification} from "script/verification/VaultVerification.sol";


contract VaultConfigureUpgradeTest is Test, MainnetActors {

    function test_configure() public {
        Vault vault = Vault(payable(MC.YNETHX));
        Withdrawer withdrawer;
        uint256 previousTotalAssets = vault.totalAssets();

        {
            vm.expectRevert();
            vault.VAULT_VERSION();
        }

        {
            // upgrade the vault
            Vault vaultImpl = Vault(payable(new YnETHxVault()));

            TimelockController timelock = TimelockController(payable(MC.TIMELOCK));

            // schedule a proxy upgrade transaction on the timelock
            // the traget is the proxy admin for the max Vault Proxy Contract
            address target = MC.PROXY_ADMIN;
            uint256 value = 0;

            bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

            bytes memory initData = abi.encodeWithSelector(YnETHxVault.initializeV2.selector, 18, 0);
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
            vm.stopPrank();

            configurer.configure(address(provider), address(withdrawer));
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

        VaultVerification.verifyProvider(Provider(IVault(address(vault)).provider()), withdrawer);

        VaultVerification.verifyVaultConfiguration(vault, withdrawer);
        
        VaultVerification.verifyRules(vault);

        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);
    }
}
