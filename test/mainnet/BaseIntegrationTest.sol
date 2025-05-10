// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {Provider} from "src/module/Provider.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));

        // Create a new Provider instance for testing
        Provider newProvider = new Provider();

        // Admin operations to upgrade the rate provider
        address admin = MainnetActors.ADMIN;

        Vault newVault = new Vault();
        vm.startPrank(TIMELOCK);
        ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newVault), "");
        vm.stopPrank();

        vm.startPrank(admin);

        // Grant PROVIDER_MANAGER_ROLE to admin
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        // Set the new Provider
        vault.setProvider(address(newProvider));
        // Verify the provider was updated
        assertEq(vault.provider(), address(newProvider), "Provider should be updated to new Provider");        

        vm.stopPrank();
    }
}
