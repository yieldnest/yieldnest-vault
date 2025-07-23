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
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

contract BaseIntegrationTest is Test, MainnetActors, AssertUtils {
    Vault public vault;

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));

        {
            // Grant BUFFER_MANAGER_ROLE and PROCESSOR_MANAGER_ROLE to admin
            address admin = MainnetActors.ADMIN;
            vm.startPrank(admin);
            vault.grantRole(vault.BUFFER_MANAGER_ROLE(), admin);
            vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), admin);
            vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
            vault.grantRole(vault.PROCESSOR_ROLE(), MainnetActors.PROCESSOR);
            vm.stopPrank();
        }

        {
            vm.startPrank(MainnetActors.ADMIN);
            Provider provider = new Provider();
            vault.setProvider(address(provider));
            // Set Morpho as buffer (MORPHO_MEV_CAPITAL_WETH)
            vault.setBuffer(MC.MORPHO_MEV_CAPITAL_WETH);

            // Set up SafeRules for deposit and withdraw
            SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](4);
            uint256 ruleIndex = 0;

            rules[ruleIndex++] = BaseRules.getAppendApprovalRule(MC.WETH, MC.MORPHO_MEV_CAPITAL_WETH, vault);
            rules[ruleIndex++] = BaseRules.getDepositRule(MC.MORPHO_MEV_CAPITAL_WETH, address(vault));
            rules[ruleIndex++] = BaseRules.getWithdrawRule(MC.MORPHO_MEV_CAPITAL_WETH, address(vault));
            rules[ruleIndex++] = BaseRules.getRedeemRule(MC.MORPHO_MEV_CAPITAL_WETH, address(vault));

            SafeRules.setProcessorRules(vault, rules, true);

            vm.stopPrank();
        }
    }
}
