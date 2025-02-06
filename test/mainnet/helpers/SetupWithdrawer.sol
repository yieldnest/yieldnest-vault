// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TimelockController, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";

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
        Withdrawer implementation = new Withdrawer();

        Provider provider = new Provider();

        address timelock = _deployTimelockController();

        // Deploy the proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), timelock, "");

        vault = Withdrawer(payable(address(proxy)));

        WithdrawerConfig.configure(vault, address(provider), timelock, address(this), IActors(address(this)));
    }
}
