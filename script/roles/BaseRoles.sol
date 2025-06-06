// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Vault} from "src/Vault.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {IActors} from "script/Actors.sol";

library BaseRoles {
    function configureDefaultRoles(Vault vault, address timelock, IActors actors) internal {
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
        vault.grantRole(vault.FEE_MANAGER_ROLE(), timelock);
    }

    function configureDefaultRolesForBufferStrategy(BufferStrategy bufferStrategy, address vault, address timelock, IActors actors) internal {
        configureDefaultRoles(Vault(payable(address(bufferStrategy))), timelock, actors);
        bufferStrategy.grantRole(bufferStrategy.MORPHO_USDC_CORE_VAULT_MANAGER_ROLE(), actors.MORPHO_USDC_CORE_VAULT_MANAGER());
        bufferStrategy.grantRole(bufferStrategy.DEPOSIT_MANAGER_ROLE(), actors.DEPOSIT_MANAGER());
        bufferStrategy.grantRole(bufferStrategy.ALLOCATOR_MANAGER_ROLE(), actors.ALLOCATOR_MANAGER());
        bufferStrategy.grantRole(bufferStrategy.ALLOCATOR_ROLE(), vault);
    }

    function configureTemporaryRolesForBufferStrategy(BufferStrategy bufferStrategy) internal {
        configureTemporaryRoles(Vault(payable(address(bufferStrategy))), address(this));
        bufferStrategy.grantRole(bufferStrategy.MORPHO_USDC_CORE_VAULT_MANAGER_ROLE(), address(this));
        bufferStrategy.grantRole(bufferStrategy.DEPOSIT_MANAGER_ROLE(), address(this));
        bufferStrategy.grantRole(bufferStrategy.ALLOCATOR_MANAGER_ROLE(), address(this));
    }

    function configureTemporaryRoles(Vault vault) internal {
        configureTemporaryRoles(vault, address(this));
    }

    function configureTemporaryRoles(Vault vault, address deployer) internal {
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        vault.grantRole(vault.PROCESSOR_ROLE(), deployer);
        vault.grantRole(vault.PAUSER_ROLE(), deployer);
        vault.grantRole(vault.UNPAUSER_ROLE(), deployer);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), deployer);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), deployer);
    }

    function configureTemporaryRolesForMaxVault(Vault vault, address deployer) internal {
        configureTemporaryRoles(vault, deployer);
            vault.grantRole(vault.FEE_MANAGER_ROLE(), deployer);

    }

    function renounceTemporaryRolesForBufferStrategy(BufferStrategy bufferStrategy, address deployer) internal {
        renounceTemporaryRoles(Vault(payable(address(bufferStrategy))), deployer);
        bufferStrategy.renounceRole(bufferStrategy.MORPHO_USDC_CORE_VAULT_MANAGER_ROLE(), deployer);
        bufferStrategy.renounceRole(bufferStrategy.DEPOSIT_MANAGER_ROLE(), deployer);
        bufferStrategy.renounceRole(bufferStrategy.ALLOCATOR_MANAGER_ROLE(), deployer);
    }

    function renounceTemporaryRoles(Vault vault, address deployer) internal {
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);
        vault.renounceRole(vault.PROCESSOR_ROLE(), deployer);
        vault.renounceRole(vault.PAUSER_ROLE(), deployer);
        vault.renounceRole(vault.UNPAUSER_ROLE(), deployer);
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), deployer);
    }

    function renounceTemporaryRolesForMaxVault(Vault vault, address deployer) internal {
        renounceTemporaryRoles(vault, deployer);
            vault.renounceRole(vault.FEE_MANAGER_ROLE(), deployer);

    }
}