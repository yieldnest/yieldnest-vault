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
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    FeeHooks public hooks;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));
        vault.processAccounting();

        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });

        hooks = new FeeHooks(address(vault), ADMIN, 1e17, ADMIN, config);

        address implAddress = 0x9C1713BC42dCF621038F4016664fFAB096A05410;
        Vault newImplementation = Vault(payable(implAddress));
        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(newImplementation)
        );
        // vm.startPrank(ADMIN);
        // vault.grantRole(vault.HOOKS_MANAGER_ROLE(), ADMIN);
        // vault.setHooks(address(hooks));
        // vm.stopPrank();
        // vault.processAccounting();

        // TODO: remove this
        vm.startPrank(ADMIN);
        VaultVerification.getWithdrawer(vault).unpause();
        vm.stopPrank();
    }
}
