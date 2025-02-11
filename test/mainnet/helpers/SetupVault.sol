// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";

contract SetupVault is Test, MainnetActors {
    function upgrade() public {
        Vault newVault = Vault(payable(new YnETHxVault()));

        TimelockController timelock = TimelockController(payable(MC.TIMELOCK));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin for the max Vault Proxy Contract
        address target = MC.PROXY_ADMIN;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        bytes memory initData = abi.encodeWithSelector(YnETHxVault.initializeV2.selector, 18, 0);
        bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(newVault), initData);

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

        Vault vault = Vault(payable(MC.YNETHX));

        assertEq(vault.symbol(), "ynETHx");

        configure(vault);
    }

    function configure(Vault vault) internal {
        assertTrue(vault.paused(), "Vault should be paused");

        YnETHxConfigurer configurer = new YnETHxConfigurer();
        SetupWithdrawer setup = new SetupWithdrawer();
        Withdrawer withdrawer = setup.setup();
        Provider provider = new Provider();

        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(configurer));

        // the following roles are granted to the admin for testing purposes
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), ADMIN);
       

        configurer.configure(address(provider), address(withdrawer));
        vm.stopPrank();
        assertFalse(vault.paused(), "Vault should not be paused");

        vault.processAccounting();
    }

    function deployViewer(Vault vault_) public returns (MaxVaultViewer viewer) {
        MaxVaultViewer implementation = new MaxVaultViewer();

        bytes memory initData =
            abi.encodeWithSelector(MaxVaultViewer.initialize.selector, address(vault_), address(ADMIN));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), ADMIN, initData);
        viewer = MaxVaultViewer(payable(address(proxy)));

        vm.startPrank(ADMIN);
        viewer.grantRole(viewer.UPDATER_ROLE(), ADMIN);
        vm.stopPrank();
    }
}
