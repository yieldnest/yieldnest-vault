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

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    WrappedToken public wusdc;

    function setUp() public virtual {
                string memory name = "YieldNest RWA MAX";
        string memory symbol = "ynRWAx";

        Vault vaultImplementation = new PublicViewsVault();

        // Deploy the proxy
        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, "");

        vault = Vault(payable(address(vaultProxy)));

        // Initialize the vault
        // Initialize the vault with the following parameters:
        // ADMIN: The address that will have admin privileges
        // name: The name of the vault token ("YieldNest RWA MAX")
        // symbol: The symbol of the vault token ("ynRWAx")
        // 18: The number of decimals for the vault token
        // 0: The withdrawal fee in basis points (0 = no fee)
        // false: Whether to count native assets (ETH) in the vault
        // true: Whether to always compute total assets (instead of tracking incrementally)
        // 1: The default asset index to use (the second asset added will be default)
        vault.initialize(ADMIN, name, symbol, 18, 0, false, true, 1);


        wusdc = WrappedToken(address(new TUProxy(address(new WrappedToken()), ADMIN, "")));
        wusdc.initialize(IERC20(MC.USDC), "Wrapped USDC", "wUSDC", 18, 12);

        configureMainnet(vault);
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

        Provider provider = new Provider();
        // Set the provider to the 6 decimals provider
        vault.setProvider(address(provider));

        // Add assets: Base asset (USDC) first, then WBTC and an 18 decimal asset

        vault.addAsset(address(wusdc), true);
        vault.addAsset(MC.USDC, true); // USDC mocked at WETH address
        vault.addAsset(MC.BUFFER, false);
    }
}
