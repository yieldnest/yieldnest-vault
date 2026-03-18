// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {ProxyAdmin} from "src/Common.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {FeeHooks} from "src/hooks/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract BaseIntegrationTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNBNBX));


        // Set the provider in the vault
        vm.startPrank(MC.TIMELOCK);
        vault.setProvider(address(new Provider()));
        vm.stopPrank();

        runCustomUpgrade();

        mockKernelVaultDepositLimit(MC.WBNB);
        mockKernelVaultDepositLimit(MC.CLISBNB);
        mockKernelVaultDepositLimit(MC.SLISBNB);
    }

    function upgradeVaults() public {
        // Get initial values to verify after upgrade
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Deploy a new Provider
        Provider provider = new Provider();

        // Set the provider in the vault
        vm.startPrank(MC.TIMELOCK);

        // Execute the Upgrade ATOMICALLY at upgrade time
        {
            Vault newVault = new Vault();
            ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(vault)), address(newVault), ""
            );
        }

        vault.setProvider(address(provider));
        vm.stopPrank();

        // Assert that totalAssets and totalSupply stayed the same after upgrade
        assertEq(vault.totalAssets(), initialTotalAssets, "Total assets should remain unchanged after upgrade");
        assertEq(vault.totalSupply(), initialTotalSupply, "Total supply should remain unchanged after upgrade");
    }

    function runCustomUpgrade() public {
        // Get initial values to verify after upgrade
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ADMIN);

        vault.setAlwaysComputeTotalAssets(false);

        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), ADMIN);

        address metahooks = 0xE414ae862DD848DAdfea633d2BE5db4a369E2695;
        vault.setHooks(metahooks);

        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), ADMIN);
        vm.stopPrank();

        // Assert that totalAssets and totalSupply stayed the same after upgrade
        assertEq(vault.totalAssets(), initialTotalAssets, "Total assets should remain unchanged after upgrade");
        assertEq(vault.totalSupply(), initialTotalSupply, "Total supply should remain unchanged after upgrade");
    }

    function mockKernelVaultDepositLimit(address asset) public {
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(asset);
        address config = IKernelVault(kernelVault).getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);

        assertEq(IKernelVault(kernelVault).getDepositLimit(), type(uint256).max, "Deposit limit should be max");
    }

    function unpauseKernelVaultsDeposit(address asset) public {
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(asset);
        address config = IKernelVault(kernelVault).getConfig();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).unpauseFunctionality("VAULTS_DEPOSIT");
    }
}
