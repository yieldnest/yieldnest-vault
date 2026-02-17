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
import {MockProvider} from "test/mainnet/mocks/MockProvider.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {Provider} from "src/module/Provider.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {DeployMaxVault} from "script/DeployMaxVault.s.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    WrappedToken public wusdc;
    MaxVaultViewer public viewer;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNRWAX));

        viewer = MaxVaultViewer(MC.YNRWAX_VIEWER);
        wusdc = WrappedToken(MC.WUSDC);

        // Upgrade vault to latest implementation (v0.4.2)
        Vault newImplementation = new Vault();
        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(newImplementation)
        );
    }
}
