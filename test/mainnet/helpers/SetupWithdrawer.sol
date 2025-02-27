// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {WithdrawerConfigurer} from "src/configures/WithdrawerConfigurer.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";

contract SetupWithdrawer is Test, MainnetActors, Etches {
    error InvalidRules();

    function setup() public returns (Withdrawer vault) {
        // vm.etch(MC.SLIS_BNB_STAKE_HUB, code);
        mockStakeHub();

        Withdrawer implementation = new Withdrawer();

        Provider provider = new Provider();

        // Deploy the proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), MC.TIMELOCK, "");

        vault = Withdrawer(payable(address(proxy)));

        WithdrawerConfigurer configurer = new WithdrawerConfigurer();
        configurer.configure(vault, address(provider), MC.TIMELOCK, IActors(address(this)));
    }
}
