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
import {Provider} from "src/module/Provider.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {IVault} from "src/interface/IVault.sol";

contract SetupWithdrawer is Test, MainnetActors {
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

        {
            // ynETH withdrawal queue
            BaseRules.RuleParams memory ynEthRuleParams = BaseRules.getApprovalRule(vault, MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            vault.setProcessorRule(ynEthRuleParams.contractAddress, ynEthRuleParams.funcSig, ynEthRuleParams.rule);
            WithdrawerRules.setRequestWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
            WithdrawerRules.setClaimWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
        }

        {
            // ynLSDe withdrawal queue
            BaseRules.RuleParams memory ynLsDeRuleParams = BaseRules.getApprovalRule(vault, MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            vault.setProcessorRule(ynLsDeRuleParams.contractAddress, ynLsDeRuleParams.funcSig, ynLsDeRuleParams.rule);
            WithdrawerRules.setRequestWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
            WithdrawerRules.setClaimWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
        }

        {
            // wstETH withdrawal queue
            BaseRules.RuleParams memory wstEthRuleParams = BaseRules.getApprovalRule(vault, MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
            vault.setProcessorRule(wstEthRuleParams.contractAddress, wstEthRuleParams.funcSig, wstEthRuleParams.rule);
            WithdrawerRules.setRequestWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);
            WithdrawerRules.setClaimWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);
        }

        // NOTE: woeth withdrawal is handled via direct methods on the vault

        {
            // wrap/unwrap wstETH
            (address wsteth_, bytes4 funcSig, IVault.FunctionRule memory rule) = StakedEtherRules.getWrapRule(vault, MC.WSTETH);
            vault.setProcessorRule(wsteth_, funcSig, rule);
            StakedEtherRules.setUnwrapRule(vault, MC.WSTETH);
            vault.setProcessorRule(wsteth_, funcSig, rule);
        }

        {
            // wrap/unwrap woeth
            BaseRules.RuleParams memory woethDepositRuleParams = BaseRules.getDepositRule(vault, MC.WOETH);
            vault.setProcessorRule(woethDepositRuleParams.contractAddress, woethDepositRuleParams.funcSig, woethDepositRuleParams.rule);
            BaseRules.RuleParams memory woethWithdrawRuleParams = BaseRules.getWithdrawRule(vault, MC.WOETH);
            vault.setProcessorRule(woethWithdrawRuleParams.contractAddress, woethWithdrawRuleParams.funcSig, woethWithdrawRuleParams.rule);
            BaseRules.RuleParams memory woethRedeemRuleParams = BaseRules.getRedeemRule(vault, MC.WOETH);
            vault.setProcessorRule(woethRedeemRuleParams.contractAddress, woethRedeemRuleParams.funcSig, woethRedeemRuleParams.rule);
        }

        vault.unpause();

        BaseRoles.renounceTemporaryRoles(vault);
    }
}
