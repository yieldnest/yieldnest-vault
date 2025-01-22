// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {WithdrawerUtils} from "script/WithdrawerUtils.sol";

contract SetupWithdrawer is Test, Etches, MainnetActors, WithdrawerUtils {
    function setup() public returns (Withdrawer vault) {
        string memory name = "YieldNest Withdrawer";
        string memory symbol = "ynWithdrawer";

        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, "");

        vault = Withdrawer(payable(address(vaultProxy)));

        vm.prank(ADMIN);
        vault.initialize(ADMIN, name, symbol, 18, true, false);

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
        vault.addAsset(MC.STETH, true, true);
        vault.addAsset(MC.WSTETH, true, true);
        vault.addAsset(MC.METH, true, true);
        vault.addAsset(MC.RETH, true, true);
        vault.addAsset(MC.WOETH, true, true);
        vault.addAsset(MC.SWELL, true, true);
        vault.addAsset(MC.SFRXETH, true, true);
        vault.addAsset(MC.YNLSDE, true, true);
        vault.addAsset(MC.YNETH, true, true);

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
