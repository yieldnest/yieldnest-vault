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
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));

        upgradeVaults();
    }

    function upgradeVaults() internal {
        vault.processAccounting();
        // Capture values before upgrade
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Create a new Provider instance for testing
        Provider newProvider = new Provider();

        vm.startPrank(TIMELOCK);
        {
            Vault newVault = new Vault();

            ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault))).upgradeAndCall(
                ITransparentUpgradeableProxy(address(vault)), address(newVault), ""
            );

            assertEq(
                ProxyUtils.getImplementation(address(vault)),
                address(newVault),
                "Vault implementation should be updated correctly"
            );
        }

        {
            // Get the current withdrawer from the vault
            Withdrawer currentWithdrawer = VaultVerification.getWithdrawer(vault);

            // Create a new Withdrawer instance
            Withdrawer newWithdrawer = new Withdrawer();

            // Upgrade the withdrawer proxy
            ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(address(currentWithdrawer)));
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(address(currentWithdrawer)), address(newWithdrawer), ""
            );

            // Assert that the withdrawer implementation was updated correctly
            assertEq(
                ProxyUtils.getImplementation(address(currentWithdrawer)),
                address(newWithdrawer),
                "Withdrawer implementation should be updated correctly"
            );
        }
        // Set the new Provider
        vault.setProvider(address(newProvider));
        // Verify the provider was updated
        assertEq(vault.provider(), address(newProvider), "Provider should be updated to new Provider");

        vm.stopPrank();

        vault.processAccounting();

        // Assert that totalAssets and totalSupply remain unchanged after the upgrade
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged after upgrade");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged after upgrade");
    }
}
