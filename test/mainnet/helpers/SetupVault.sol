// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHx} from "src/YnETHx.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

contract SetupVault is Test, MainnetActors {
    function deployViewer(Vault vault_) public returns (MaxVaultViewer viewer) {
        MaxVaultViewer implementation = new MaxVaultViewer();

        bytes memory initData =
            abi.encodeWithSelector(MaxVaultViewer.initialize.selector, address(vault_), address(ADMIN));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), ADMIN, initData);
        viewer = MaxVaultViewer(payable(address(proxy)));

        vm.startPrank(ADMIN);
        viewer.grantRole(viewer.UPDATER_ROLE(), ADMIN);
        vm.stopPrank();
    }
}
