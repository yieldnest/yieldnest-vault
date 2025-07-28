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
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {Hooks} from "src/Hooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {YnETHx} from "src/YnETHx.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    Hooks public hooks;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));
        vault.processAccounting();

        Hooks hooksImplementation = new Hooks(address(vault));
        TransparentUpgradeableProxy hooksProxy =
            new TransparentUpgradeableProxy(address(hooksImplementation), ADMIN, "");
        hooks = Hooks(payable(address(hooksProxy)));
        hooks.initialize(ADMIN, 1e17, ADMIN);

        Vault newImplementation = new YnETHx();
        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(newImplementation)
        );
        YnETHx(payable(address(vault))).initializeV3(address(hooks));
    }
}
