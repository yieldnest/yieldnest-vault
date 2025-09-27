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
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract BaseIntegrationTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNBNBX));

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

        // Deploy a new Provider
        Provider provider = new Provider();

        // Set the provider in the vault
        // vm.startPrank(MC.TIMELOCK);

        // // Execute the Upgrade ATOMICALLY at upgrade time
        // {
        //     address vaultImplementation = 0xA94F95aC2Da2f94f25339B84bA6EdB80E4f2108B;
        //     Vault newVault = Vault(payable(vaultImplementation));
        //     ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault))).upgradeAndCall(
        //         ITransparentUpgradeableProxy(address(vault)), address(newVault), ""
        //     );
        // }
        // vm.stopPrank();

        // TODO: re-enable this with fee-hooks

        // vm.startPrank(MC.TIMELOCK);
        // vault.setProvider(address(provider));
        // vm.stopPrank();

        // FeeHooks feeHooks = new FeeHooks(
        //     address(vault),
        //     ADMIN,
        //     1e17, // 10% performance fee
        //     ADMIN,
        //     IHooks.Config({
        //         beforeDeposit: false,
        //         afterDeposit: false,
        //         beforeMint: false,
        //         afterMint: false,
        //         beforeRedeem: false,
        //         afterRedeem: false,
        //         beforeWithdraw: false,
        //         afterWithdraw: false,
        //         beforeProcessAccounting: false,
        //         afterProcessAccounting: true
        //     })
        // );

        // vm.startPrank(MC.TIMELOCK);
        // vault.setAlwaysComputeTotalAssets(false);
        // vm.stopPrank();

        // vm.startPrank(ADMIN);
        // vault.grantRole(vault.HOOKS_MANAGER_ROLE(), MC.TIMELOCK);
        // vm.stopPrank();

        // vm.startPrank(MC.TIMELOCK);
        // vault.setHooks(address(feeHooks));
        // vm.stopPrank();

        // {
        //     address[] memory targets = new address[](1);
        //     targets[0] = 0xFca05CD06AA2856950Eab7F44731CFF68546271e;

        //     uint256[] memory values = new uint256[](1);
        //     values[0] = 0;

        //     bytes[] memory payloads = new bytes[](1);
        //     payloads[0] =
        //         hex"9623609d00000000000000000000000032c830f5c34122c6afb8ae87aba541b7900a2c5f000000000000000000000000a94f95ac2da2f94f25339b84ba6edb80e4f2108b00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000";

        //     bytes32 predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;
        //     bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000000;

        //     vm.startPrank(ADMIN);
        //     TimelockController(payable(MC.TIMELOCK)).executeBatch(targets, values, payloads, predecessor, salt);
        //     vm.stopPrank();
        // }

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
}
