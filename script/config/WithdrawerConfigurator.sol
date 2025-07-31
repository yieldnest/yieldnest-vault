// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IActors} from "script/Actors.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";

contract WithdrawerConfigurator {
    function configure(Withdrawer vault, address provider, address timelock, IActors actors) public {
        WithdrawerConfig.configure(vault, provider, timelock, address(this), actors);
    }
}
