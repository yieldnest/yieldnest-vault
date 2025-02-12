// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

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
}
