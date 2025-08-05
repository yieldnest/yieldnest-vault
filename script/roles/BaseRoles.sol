// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseVault} from "src/BaseVault.sol";
import {IActors} from "script/Actors.sol";

library BaseRoles {
    function configureDefaultRoles(BaseVault vault, address timelock, IActors actors) internal {
        // set admin roles
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
        vault.grantRole(vault.PROCESSOR_ROLE(), actors.PROCESSOR());
        vault.grantRole(vault.PAUSER_ROLE(), actors.PAUSER());
        vault.grantRole(vault.UNPAUSER_ROLE(), actors.UNPAUSER());
        // set timelock roles
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), timelock);
    }

    function configureTemporaryRoles(BaseVault vault) internal {
        configureTemporaryRoles(vault, address(this));
    }

    function configureTemporaryRoles(BaseVault vault, address deployer) internal {
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        vault.grantRole(vault.PROCESSOR_ROLE(), deployer);
        vault.grantRole(vault.PAUSER_ROLE(), deployer);
        vault.grantRole(vault.UNPAUSER_ROLE(), deployer);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), deployer);
    }

    function configureTemporaryRolesForMaxVault(BaseVault vault, address deployer) internal {
        configureTemporaryRoles(vault, deployer);
    }

    function renounceTemporaryRoles(BaseVault vault, address deployer) internal {
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        vault.renounceRole(vault.PROCESSOR_ROLE(), deployer);
        vault.renounceRole(vault.PAUSER_ROLE(), deployer);
        vault.renounceRole(vault.UNPAUSER_ROLE(), deployer);
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), deployer);
    }

    function renounceTemporaryRolesForMaxVault(BaseVault vault, address deployer) internal {
        renounceTemporaryRoles(vault, deployer);
    }
}
