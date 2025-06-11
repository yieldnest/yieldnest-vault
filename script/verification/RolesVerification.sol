// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {IActors} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

import {console} from "lib/forge-std/src/console.sol";

library RolesVerification {
    function verifyRole(IAccessControl control, address account, bytes32 role, bool expected, string memory message)
        internal
        view
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        bool hasRole = control.hasRole(role, account);
        console.log(hasRole == expected ? "\u2705" : "\u274C", message, account);
        vm.assertEq(hasRole, expected, message);
    }

    function verifyDefaultRoles(BaseVault vault, TimelockController timelock, IActors actors) internal view {
        // verify actors roles
        verifyRole(vault, actors.ADMIN(), vault.DEFAULT_ADMIN_ROLE(), true, "Admin has DEFAULT_ADMIN_ROLE");
        verifyRole(vault, actors.PROCESSOR(), vault.PROCESSOR_ROLE(), true, "Processor has PROCESSOR_ROLE");
        verifyRole(vault, actors.PAUSER(), vault.PAUSER_ROLE(), true, "Pauser has PAUSER_ROLE");
        verifyRole(vault, actors.UNPAUSER(), vault.UNPAUSER_ROLE(), true, "Unpauser has UNPAUSER_ROLE");

        // verify timelock roles
        verifyRole(vault, address(timelock), vault.PROVIDER_MANAGER_ROLE(), true, "Timelock has PROVIDER_MANAGER_ROLE");
        verifyRole(vault, address(timelock), vault.ASSET_MANAGER_ROLE(), true, "Timelock has ASSET_MANAGER_ROLE");
        verifyRole(vault, address(timelock), vault.BUFFER_MANAGER_ROLE(), true, "Timelock has BUFFER_MANAGER_ROLE");
        verifyRole(
            vault, address(timelock), vault.PROCESSOR_MANAGER_ROLE(), true, "Timelock has PROCESSOR_MANAGER_ROLE"
        );
    }

    function verifyTemporaryRoles(BaseVault vault, address deployer) internal view {
        verifyRole(vault, deployer, vault.DEFAULT_ADMIN_ROLE(), false, "Deployer does not have DEFAULT_ADMIN_ROLE");
        verifyRole(
            vault, deployer, vault.PROCESSOR_MANAGER_ROLE(), false, "Deployer does not have PROCESSOR_MANAGER_ROLE"
        );
        verifyRole(vault, deployer, vault.BUFFER_MANAGER_ROLE(), false, "Deployer does not have BUFFER_MANAGER_ROLE");
        verifyRole(
            vault, deployer, vault.PROVIDER_MANAGER_ROLE(), false, "Deployer does not have PROVIDER_MANAGER_ROLE"
        );
        verifyRole(vault, deployer, vault.ASSET_MANAGER_ROLE(), false, "Deployer does not have ASSET_MANAGER_ROLE");
        verifyRole(vault, deployer, vault.UNPAUSER_ROLE(), false, "Deployer does not have UNPAUSER_ROLE");
        verifyRole(vault, deployer, vault.PAUSER_ROLE(), false, "Deployer does not have PAUSER_ROLE");
        verifyRole(vault, deployer, vault.PROCESSOR_ROLE(), false, "Deployer does not have PROCESSOR_ROLE");
    }

    function verifyViewerRoles(MaxVaultViewer viewer, IActors actors, address deployer) internal view {
        verifyRole(viewer, actors.ADMIN(), viewer.DEFAULT_ADMIN_ROLE(), true, "Admin has DEFAULT_ADMIN_ROLE");
        verifyRole(viewer, actors.UPDATER(), viewer.UPDATER_ROLE(), true, "Updated has UPDATER_ROLE");
        verifyRole(viewer, deployer, viewer.DEFAULT_ADMIN_ROLE(), false, "Deployer does not have DEFAULT_ADMIN_ROLE");
        verifyRole(viewer, deployer, viewer.UPDATER_ROLE(), false, "Deployer does not have UPDATER_ROLE");
    }

    function verifyProxyRoles(address proxy, address proxyAdmin, address proxyAdminOwner) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        bool isProxyAdmin = ProxyUtils.getProxyAdmin(proxy) == proxyAdmin;
        console.log(isProxyAdmin ? "\u2705" : "\u274C", "Proxy admin is correct:", proxyAdmin);
        vm.assertTrue(isProxyAdmin, "Proxy admin is not correct");

        bool isProxyAdminOwner = Ownable(ProxyUtils.getProxyAdmin(proxy)).owner() == proxyAdminOwner;
        console.log(isProxyAdminOwner ? "\u2705" : "\u274C", "Proxy admin owner is correct:", proxyAdminOwner);
        vm.assertTrue(isProxyAdminOwner, "Proxy admin owner is not correct");
    }

    function verifyTimelockRoles(TimelockController timelock, IActors actors, uint256 minDelay) internal view {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        bool isMinDelay = timelock.getMinDelay() == minDelay;
        console.log(isMinDelay ? "\u2705" : "\u274C", "Timelock min delay is correct:", minDelay);
        vm.assertTrue(isMinDelay, "Timelock min delay is not correct");

        verifyRole(timelock, actors.PROPOSER_1(), timelock.PROPOSER_ROLE(), true, "Proposer 1 has PROPOSER_ROLE");
        verifyRole(timelock, actors.EXECUTOR_1(), timelock.EXECUTOR_ROLE(), true, "Executor 1 has EXECUTOR_ROLE");
        verifyRole(timelock, actors.ADMIN(), timelock.DEFAULT_ADMIN_ROLE(), true, "Admin has DEFAULT_ADMIN_ROLE");
    }
}
