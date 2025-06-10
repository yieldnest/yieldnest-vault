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
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {DeployMaxVault} from "script/DeployMaxVault.s.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    WrappedToken public wusdc;
    MaxVaultViewer public viewer;

    function setUp() public virtual {
                string memory name = "YieldNest RWA MAX";
        string memory symbol = "ynRWAx";

        DeployMaxVault deployMaxVault = new DeployMaxVault(); 
        deployMaxVault.run();

        vault = deployMaxVault.vault();

        viewer = MaxVaultViewer(address(deployMaxVault.viewer()));
        wusdc = deployMaxVault.wusdc();
    } 

    function configureMainnet(Vault vault) internal {

        vm.startPrank(ADMIN);

        // Grant roles
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        Provider provider = new Provider(address(wusdc));
        // Set the provider to the 6 decimals provider
        vault.setProvider(address(provider));

        // Add assets: Base asset (USDC) first, then WBTC and an 18 decimal asset

        vault.addAsset(address(wusdc), true);
        vault.addAsset(MC.USDC, true); // USDC mocked at WETH address

        vault.unpause();

        vm.stopPrank();
    }
}
