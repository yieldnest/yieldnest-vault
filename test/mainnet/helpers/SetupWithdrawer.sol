// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TimelockController, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {StakedEtherRules} from "script/rules/StakedEtherRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {Provider} from "src/module/Provider.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";

contract SetupWithdrawer is Test, MainnetActors {
    error InvalidRules();

    function _deployTimelockController() internal virtual returns (address) {
        uint256 minDelay = 1 days;

        address[] memory proposers = new address[](1);
        proposers[0] = PROPOSER_1;

        address[] memory executors = new address[](1);
        executors[0] = EXECUTOR_1;

        TimelockController timelock = new TimelockController(minDelay, proposers, executors, ADMIN);
        return address(timelock);
    }

    function setup() public returns (Withdrawer vault) {
        Withdrawer vaultImplementation = new Withdrawer();

        address timelock = _deployTimelockController();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), timelock, "");

        vault = Withdrawer(payable(address(vaultProxy)));

        {
            // initialize
            string memory name = "YieldNest Withdrawer";
            string memory symbol = "ynWithdrawer";
            uint8 decimals_ = 18;
            bool countNativeAsset_ = true;
            bool alwaysComputeTotalAssets_ = false;

            vault.initialize(address(this), name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
        }

        Provider provider = new Provider();

        _configureWithdrawer(vault, address(provider), timelock);
    }

    function _configureWithdrawer(Withdrawer vault, address provider, address timelock) internal {
        {
            // configure roles
            BaseRoles.configureDefaultRoles(vault, timelock, IActors(address(this)));
            BaseRoles.configureTemporaryRoles(vault);
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
            vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        }

        // set the rate provider contract
        vault.setProvider(provider);

        {
            // add assets: Base asset always first
            vault.addAsset(MC.WETH, true, true);
            vault.addAsset(MC.STETH, true, false);
            vault.addAsset(MC.WSTETH, true, false);
            vault.addAsset(MC.METH, true, false);
            vault.addAsset(MC.RETH, true, false);
            vault.addAsset(MC.WOETH, true, false);
            vault.addAsset(MC.OETH, true, false);
            vault.addAsset(MC.SWELL, true, false);
            vault.addAsset(MC.SFRXETH, true, false);
            vault.addAsset(MC.YNLSDE, true, false);
            vault.addAsset(MC.YNETH, true, false);
        }

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](14);
        uint256 ruleIndex = 0;

        {
            // ynETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNETH_WITHDRAWAL_QUEUE_MANAGER, address(vault));
        }

        {
            // ynLSDe withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] = WithdrawerRules.getRequestWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalRule(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, address(vault));
        }

        {
            // wstETH withdrawal queue
            rules[ruleIndex++] = BaseRules.getApprovalRule(MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
            rules[ruleIndex++] =
                WithdrawerRules.getRequestWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(vault));
            rules[ruleIndex++] =
                WithdrawerRules.getClaimWithdrawalWstETHRule(MC.WSTETH_WITHDRAWAL_QUEUE, address(vault));
        }

        // NOTE: woeth withdrawal is handled via direct methods on the vault

        {
            // wrap/unwrap wstETH
            rules[ruleIndex++] = StakedEtherRules.getWrapRule(MC.WSTETH);
            rules[ruleIndex++] = StakedEtherRules.getUnwrapRule(MC.WSTETH);
        }

        {
            // wrap/unwrap woeth
            rules[ruleIndex++] = BaseRules.getDepositRule(MC.WOETH, address(vault));
            rules[ruleIndex++] = BaseRules.getWithdrawRule(MC.WOETH, address(vault));
            rules[ruleIndex++] = BaseRules.getRedeemRule(MC.WOETH, address(vault));
        }

        if (ruleIndex != rules.length) {
            revert InvalidRules();
        }

        SafeRules.setProcessorRules(vault, rules);

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault);
    }
}
