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

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    WrappedToken public wusdc;
    MaxVaultViewer public viewer;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNRWAX));

        viewer = MaxVaultViewer(MC.YNRWAX_VIEWER);
        wusdc = WrappedToken(MC.WUSDC);

        addRWAStrategy();
    }

    function addRWAStrategy() public {
        // Deploy new provider
        Provider newProvider = new Provider(MC.WUSDC);

        // Set the new provider on the vault
        vm.startPrank(TIMELOCK);
        vault.setProvider(address(newProvider));
        vm.stopPrank();

        vm.startPrank(TIMELOCK);
        vault.addAsset(MC.FLEX_STRATEGY_USDC, false);
        vm.stopPrank();

        // Add approval rule for FLEX_STRATEGY_USDC
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(MC.USDC, MC.FLEX_STRATEGY_USDC);

        // Add deposit rule for FLEX_STRATEGY_USDC
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(MC.FLEX_STRATEGY_USDC, address(vault));

        // Set the processor rules for the vault
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        rules[0] = approvalRule;
        rules[1] = depositRule;

        vm.startPrank(TIMELOCK);
        SafeRules.setProcessorRules(vault, rules);
        vm.stopPrank();
    }
}
