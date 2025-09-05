// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Vault} from "src/Vault.sol";

contract SetupWithdrawer is Test, MainnetActors {
    error InvalidRules();

    function setup() public returns (Withdrawer vault) {
        Withdrawer implementation = new Withdrawer();

        Provider provider = new Provider();

        // Deploy the proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), MC.TIMELOCK, "");

        vault = Withdrawer(payable(address(proxy)));

        WithdrawerConfig.configure(vault, address(provider), MC.TIMELOCK, address(this), IActors(address(this)));
    }

    function upgradeWithdrawerAndVault(Withdrawer withdrawer) public {
        Withdrawer implementation = new Withdrawer();
        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(MC.TIMELOCK)), ADMIN, address(withdrawer), address(implementation)
        );

        Provider provider = new Provider();
        vm.prank(MC.TIMELOCK);
        withdrawer.setProvider(address(provider));

        Vault newImplementation = new Vault();
        Vault vault = Vault(payable(MC.YNETHX));
        UpgradeUtils.timelockUpgrade(
            TimelockController(payable(MC.TIMELOCK)), ADMIN, address(vault), address(newImplementation)
        );

        vm.prank(MC.TIMELOCK);
        vault.setProvider(address(provider));

        vm.startPrank(ADMIN);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), MC.TIMELOCK);
        vm.stopPrank();
    }
}
