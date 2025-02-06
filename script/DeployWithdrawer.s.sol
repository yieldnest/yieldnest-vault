// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "./ProxyUtils.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {StakedEtherRules} from "script/rules/StakedEtherRules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";

contract DeployWithdrawer is Script {
    using stdJson for string;

    Withdrawer public withdrawer;

    function label() public view returns (string memory) {
        return string.concat("Withdrawer-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment(address implementation, address proxy, address proxyAdmin) internal {
        vm.serializeAddress(label(), "deployer", msg.sender);
        vm.serializeAddress(label(), "implementation", implementation);
        vm.serializeAddress(label(), "proxy", proxy);
        vm.serializeAddress(label(), "proxyAdmin", proxyAdmin);
        string memory jsonOutput = vm.serializeAddress(label(), label(), address(withdrawer));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        vm.startBroadcast();
        Withdrawer withdrawerImplementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy withdrawerProxy =
            new TransparentUpgradeableProxy(address(withdrawerImplementation), MC.TIMELOCK, "");

        withdrawer = Withdrawer(payable(address(withdrawerProxy)));

        {
            // initialize
            string memory name = "YieldNest Withdrawer";
            string memory symbol = "ynWithdrawer";
            uint8 decimals_ = 18;
            bool countNativeAsset_ = true;
            bool alwaysComputeTotalAssets_ = false;

            withdrawer.initialize(
                MainnetActors.ADMIN, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_
            );
        }

        _configureWithdrawer(withdrawer, address(MC.PROVIDER), MC.TIMELOCK);

        saveDeployment(
            address(withdrawerImplementation), address(withdrawerProxy), ProxyUtils.getProxyAdmin(withdrawerProxy)
        );

        vm.stopBroadcast();
    }

    function _configureWithdrawer(Withdrawer withdrawer, address provider, address timelock) internal {
        {
            // configure roles
            BaseRoles.configureDefaultRoles(withdrawer, timelock, IActors(MainnetActors.ADMIN));
            BaseRoles.configureTemporaryRoles(withdrawer);
            withdrawer.grantRole(withdrawer.DEFAULT_ADMIN_ROLE(), MainnetActors.ADMIN);
            withdrawer.grantRole(withdrawer.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        }

        // set the rate provider contract
        withdrawer.setProvider(provider);

        {
            // add assets: Base asset always first
            withdrawer.addAsset(MC.WETH, true, true);
            withdrawer.addAsset(MC.STETH, true, false);
            withdrawer.addAsset(MC.WSTETH, true, false);
            withdrawer.addAsset(MC.METH, true, false);
            withdrawer.addAsset(MC.RETH, true, false);
            withdrawer.addAsset(MC.WOETH, true, false);
            withdrawer.addAsset(MC.OETH, true, false);
            withdrawer.addAsset(MC.SWELL, true, false);
            withdrawer.addAsset(MC.SFRXETH, true, false);
            withdrawer.addAsset(MC.YNLSDE, true, false);
            withdrawer.addAsset(MC.YNETH, true, false);
        }

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](14);
        uint256 ruleIndex = 0;

        {
            // ynETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, address(withdrawer));
        }

        {
            // ynLSDe withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, address(withdrawer));
        }

        {
            // wstETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
            rules[ruleIndex++] =
                WithdrawerRules.getRequestWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(withdrawer));
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(withdrawer));
        }

        // NOTE: woeth withdrawal is handled via direct methods on the withdrawer

        {
            // wrap/unwrap wstETH
            rules[ruleIndex++] = StakedEtherRules.getWrapRule(MC.WSTETH);
            rules[ruleIndex++] = StakedEtherRules.getUnwrapRule(MC.WSTETH);
        }

        {
            // wrap/unwrap woeth
            rules[ruleIndex++] = BaseRules.getDepositRule(MC.WOETH, address(withdrawer));
            rules[ruleIndex++] = BaseRules.getWithdrawRule(MC.WOETH, address(withdrawer));
            rules[ruleIndex++] = BaseRules.getRedeemRule(MC.WOETH, address(withdrawer));
        }

        if (ruleIndex != rules.length) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(withdrawer, rules);

        withdrawer.unpause();

        BaseRoles.renounceTemporaryRoles(withdrawer);
    }
}
