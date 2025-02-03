// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {WithdrawerRules} from "script/rules/WithdrawerRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

contract SetupWithdrawer is Test, MainnetActors, Etches, WithdrawerRules, BaseRules {
    function setup() public returns (Withdrawer vault) {
        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, "");

        vault = Withdrawer(payable(address(vaultProxy)));

        string memory name = "YieldNest Withdrawer";
        string memory symbol = "ynWithdrawer";
        uint8 decimals_ = 18;
        bool countNativeAsset_ = true;
        bool alwaysComputeTotalAssets_ = false;

        vm.startPrank(ADMIN);
        vault.initialize(ADMIN, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_);
        vm.stopPrank();

        configureWithdrawer(vault);
    }

    function configureWithdrawer(Withdrawer vault) internal {
        mockProvider();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);

        // test cannot unpause vault without provider
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
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

        // setup processor rules for the withdrawer
        setApprovalRule(vault, MC.YNETH, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
        setRequestWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);
        setClaimWithdrawalRule(vault, MC.YNETH_WITHDRAWAL_QUEUE_MANAGER);

        setApprovalRule(vault, MC.YNLSDE, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
        setRequestWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);
        setClaimWithdrawalRule(vault, MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER);

        setApprovalRule(vault, MC.WSTETH, MC.WSTETH_WITHDRAWAL_QUEUE);
        setRequestWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);
        setClaimWithdrawalWstETHRule(vault, MC.WSTETH_WITHDRAWAL_QUEUE);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }
}
